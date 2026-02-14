import { serve } from "https://deno.land/std@0.192.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"
import Stripe from "https://esm.sh/stripe@14.25.0?target=deno"

async function applySubscriptionPayment(
  sb: ReturnType<typeof createClient>,
  paymentId: string,
  paid: boolean,
  rawPayload: unknown
) {
  const { data: p } = await sb
    .from("payments")
    .select("id,business_id,provider,status,amount,currency,metadata,external_ref")
    .eq("id", paymentId)
    .maybeSingle()

  if (!p) return { ok: false as const, reason: "payment_not_found" }

  const meta = (p.metadata ?? {}) as Record<string, unknown>
  let metaOut: Record<string, unknown> = { ...meta, callback_payload: rawPayload }
  if (meta.purpose !== "subscription") return { ok: false as const, reason: "not_subscription" }

  if (!paid) {
    await sb
      .from("payments")
      .update({
        status: "failed",
        metadata: metaOut,
      })
      .eq("id", paymentId)

    return { ok: true as const, applied: false as const }
  }

  // Idempotent: if already paid, just return ok.
  if (p.status === "paid") return { ok: true as const, applied: false as const }

  const planCode = (meta.plan_code ?? "").toString()
  const periodDays = Number(meta.period_days ?? 30)
  if (!planCode) return { ok: false as const, reason: "missing_plan_code" }

  const { data: plan } = await sb
    .from("plans")
    .select("id,code")
    .eq("code", planCode)
    .maybeSingle()

  if (!plan) return { ok: false as const, reason: "plan_not_found" }

  const now = new Date()
  const paidUntil = new Date(now.getTime() + Math.max(1, periodDays) * 86400 * 1000)

  // Apply entitlements: plan + flags + paid-until.
  const canOrders = plan.code !== "free"
  const canAds = plan.code === "premium"
  const visibilityMultiplier = plan.code === "premium" ? 1.3 : plan.code === "pro" ? 1.1 : 1.0

  // Prefer paid-until, but stay backward-compatible if the column isn't deployed yet.
  const entBase = {
    business_id: p.business_id,
    plan_id: plan.id,
    can_receive_orders: canOrders,
    can_run_ads: canAds,
    visibility_multiplier: visibilityMultiplier,
    updated_at: now.toISOString(),
  }

  const { error: entErr } = await sb.from("entitlements").upsert({
    ...entBase,
    orders_paid_until: paidUntil.toISOString(),
  })

  if (entErr) {
    if (entErr.message?.toLowerCase().includes("orders_paid_until")) {
      await sb.from("entitlements").upsert(entBase)
    } else {
      throw entErr
    }
  }

  // Record subscription snapshot (audit). If the schema doesn't have this provider yet, the DB migration must be applied.
  const { error: subErr } = await sb.from("subscriptions").insert({
    business_id: p.business_id,
    provider: p.provider,
    status: "active",
    provider_customer_id: (meta.actor_user_id ?? null) as unknown,
    provider_subscription_id: p.id,
    product_id: plan.code,
    current_period_start: now.toISOString(),
    current_period_end: paidUntil.toISOString(),
    last_verified_at: now.toISOString(),
  })

  // Don't fail the callback if the subscription insert fails (enum/provider mismatch, etc.).
  if (subErr) {
    metaOut = { ...metaOut, subscription_insert_error: subErr.message }
  }

  await sb
    .from("payments")
    .update({
      status: "paid",
      metadata: metaOut,
    })
    .eq("id", paymentId)

  return { ok: true as const, applied: true as const }
}

serve(async (req) => {
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  // Stripe success redirect (GET)
  if (req.method === "GET") {
    const url = new URL(req.url)
    const provider = (url.searchParams.get("provider") ?? "").toLowerCase()
    const ref = url.searchParams.get("ref")
    const sessionId = url.searchParams.get("session_id")
    const cancelled = url.searchParams.get("cancelled") === "1"

    if (provider === "stripe" && ref) {
      try {
        if (cancelled) {
          await applySubscriptionPayment(sb, ref, false, { cancelled: true })
          return new Response("Payment cancelled. You can close this tab.", {
            status: 200,
            headers: { "Content-Type": "text/plain" },
          })
        }

        const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")
        if (!stripeKey) return new Response("Stripe not configured", { status: 500 })
        if (!sessionId) return new Response("Missing session_id", { status: 400 })

        const stripe = new Stripe(stripeKey, { apiVersion: "2023-10-16" })
        const session = await stripe.checkout.sessions.retrieve(sessionId)
        const paid = session.payment_status === "paid"

        const r = await applySubscriptionPayment(sb, ref, paid, {
          stripe_session_id: sessionId,
          stripe_payment_status: session.payment_status,
        })

        const msg = paid
          ? "Payment received. Return to the app and refresh your plan."
          : "Payment not completed. Return to the app."
        return new Response(msg, {
          status: r.ok ? 200 : 500,
          headers: { "Content-Type": "text/plain" },
        })
      } catch (e) {
        return new Response(`Stripe callback error: ${String(e)}`, { status: 500 })
      }
    }

    return new Response("ok", { status: 200 })
  }

  // PayDunya callback (POST JSON)
  const payload = await req.json().catch(() => null)
  if (!payload) return new Response("Missing payload", { status: 400 })

  const { custom_data, status } = payload as Record<string, unknown>
  const ref = (custom_data as any)?.reference as string | undefined

  if (!ref) return new Response("Missing ref", { status: 400 })

  if (status === "completed" || status === "success") {
    // 1) Try apply subscription payment (new flow)
    const r = await applySubscriptionPayment(sb, ref, true, payload)
    if (r.ok && (r as any).applied !== undefined) {
      return new Response("ok", { status: 200 })
    }

    // 2) Fallback: legacy order payment flow (requires DB RPC)
    await sb.rpc("apply_payment_reference", { ref })
  } else if (status === "failed") {
    const r = await applySubscriptionPayment(sb, ref, false, payload)
    if (r.ok && (r as any).applied !== undefined) {
      return new Response("ok", { status: 200 })
    }

    await sb.from("payment_intents").update({ status: "failed" }).eq("id", ref)
  }

  return new Response("ok", { status: 200 })
})
