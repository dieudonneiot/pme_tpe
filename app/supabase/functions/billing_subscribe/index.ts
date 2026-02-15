import { serve } from "https://deno.land/std@0.192.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"
import { PayDunya } from "./providers/paydunya.ts"
import Stripe from "https://esm.sh/stripe@14.25.0?target=deno"

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

serve(async (req) => {
  const body = await req.json().catch(() => ({}))
  const business_id = body?.business_id as string | undefined
  const plan_code = body?.plan_code as string | undefined
  const providerRaw = (body?.provider as string | undefined) ?? "paydunya"
  const provider = providerRaw.toLowerCase()

  if (!business_id || !plan_code) {
    return json(400, { error: "Missing business_id or plan_code" })
  }

  if (provider !== "paydunya" && provider !== "stripe") {
    return json(400, { error: "Unsupported provider" })
  }

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  const publicBaseUrl = Deno.env.get("PUBLIC_BASE_URL") ?? ""
  const callbackSecret = Deno.env.get("PAYMENTS_CALLBACK_SECRET") ?? ""

  const authHeader = req.headers.get("Authorization") ?? ""
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : ""
  const { data: { user }, error: authErr } = await sb.auth.getUser(jwt)
  if (authErr || !user) return json(401, { error: "Unauthorized" })

  // Security: ensure the caller belongs to the business (owner/admin/staff).
  const { data: member } = await sb
    .from("business_members")
    .select("role")
    .eq("business_id", business_id)
    .eq("user_id", user.id)
    .maybeSingle()

  const role = (member as { role?: string } | null)?.role ?? ""
  if (!["owner", "admin", "staff"].includes(role)) {
    return json(403, { error: "Forbidden" })
  }

  const { data: plan } = await sb
    .from("plans")
    .select("id,code,name,description,monthly_price_amount,currency")
    .eq("code", plan_code)
    .single()

  if (!plan) return json(400, { error: "Plan inconnu" })

  const amount = Number(plan.monthly_price_amount ?? 0)
  if (!Number.isFinite(amount) || amount <= 0) {
    return json(400, { error: "Plan pricing missing/invalid" })
  }

  // Create a payment row we can reconcile in callbacks (PayDunya / Stripe).
  const { data: payRow, error: payErr } = await sb
    .from("payments")
    .insert({
      business_id,
      provider,
      amount,
      currency: plan.currency ?? "XOF",
      status: "pending",
      external_ref: null,
      metadata: {
        purpose: "subscription",
        plan_code: plan.code,
        plan_id: plan.id,
        period_days: 30,
        actor_user_id: user.id,
      },
    })
    .select("id")
    .single()

  if (payErr || !payRow) {
    return json(500, { error: `DB error: ${payErr?.message ?? "unknown"}` })
  }

  const ref = payRow.id as string
  if (!publicBaseUrl) {
    await sb.from("payments").update({ status: "failed" }).eq("id", ref)
    return json(500, { error: "Payment provider not configured" })
  }

  const callbackBase = `${publicBaseUrl}/payments_callback`
  const callbackUrl = callbackSecret
    ? `${callbackBase}?cb_secret=${encodeURIComponent(callbackSecret)}`
    : callbackBase

  let paymentUrl: string | null = null

  if (provider === "paydunya") {
    try {
      paymentUrl = await PayDunya.createCheckout({
        amount,
        description: `Abonnement ${plan.name}`,
        reference: ref,
        callbackUrl,
        returnUrl: callbackBase,
        cancelUrl: callbackBase,
      })
    } catch (e) {
      const msg = (e as { message?: unknown })?.message
      const safeMsg = typeof msg === "string" ? msg : "PayDunya error"

      await sb.from("payments")
        .update({ status: "failed", metadata: { error: safeMsg } })
        .eq("id", ref)

      return json(502, { error: "Paiement indisponible. Réessaie dans un instant." })
    }

    await sb
      .from("payments")
      .update({ external_ref: paymentUrl })
      .eq("id", ref)
  } else if (provider === "stripe") {
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")
    if (!stripeKey) {
      await sb.from("payments").update({ status: "failed" }).eq("id", ref)
      return new Response("Stripe not configured", { status: 500 })
    }

    const stripe = new Stripe(stripeKey, { apiVersion: "2023-10-16" })

    const currency = (plan.currency ?? "XOF").toString().toLowerCase()
    const zeroDecimal = new Set([
      "xof",
      "xpf",
      "xaf",
      "jpy",
      "krw",
      "clp",
      "vnd",
      "gnf",
      "rwf",
      "ugx",
      "mga",
    ])
    const unitAmount = zeroDecimal.has(currency)
      ? Math.round(amount)
      : Math.round(amount * 100)

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency,
            unit_amount: unitAmount,
            product_data: {
              name: `Abonnement ${plan.name}`,
              description: plan.description ?? undefined,
            },
          },
        },
      ],
      success_url: `${callbackBase}?provider=stripe&ref=${ref}&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${callbackBase}?provider=stripe&ref=${ref}&cancelled=1`,
      metadata: {
        payment_id: ref,
        business_id,
        plan_code: plan.code,
      },
    })

    paymentUrl = session.url ?? null
    await sb
      .from("payments")
      .update({ external_ref: session.id })
      .eq("id", ref)
  }

  if (!paymentUrl) return json(500, { error: "No payment URL" })

  return json(200, { payment_url: paymentUrl, ref })
})
