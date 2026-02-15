import { serve } from "https://deno.land/std@0.192.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"
import { PayDunya } from "./providers/paydunya.ts"

function json(
  status: number,
  body: Record<string, unknown>,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  })
}

function isColumnMissingError(err: unknown, columnName: string): boolean {
  const msg = (err as { message?: unknown })?.message
  if (typeof msg !== "string") return false
  return msg.toLowerCase().includes(`column "${columnName.toLowerCase()}" does not exist`)
}

serve(async (req) => {
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  const publicBaseUrl = Deno.env.get("PUBLIC_BASE_URL") ?? ""

  const body = await req.json().catch(() => null)
  const request_id = body?.request_id
  const amount = body?.amount
  const provider = body?.provider ?? "PAYDUNYA"

  if (typeof request_id !== "string" || request_id.length === 0) {
    return json(400, { error: "request_id is required" })
  }

  if (provider !== "PAYDUNYA") {
    return json(400, { error: "Unsupported provider" })
  }

  const authHeader = req.headers.get("Authorization") ?? ""
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : ""
  if (!jwt) return json(401, { error: "Unauthorized" })

  const { data: { user }, error: authErr } = await sb.auth.getUser(jwt)
  if (authErr || !user) return json(401, { error: "Unauthorized" })

  const { data: reqRow, error: reqErr } = await (async () => {
    const base = sb.from("service_requests").eq("id", request_id)

    // Prefer the newer column name used by the Flutter app (`total_estimate`).
    const r1 = await base
      .select("id, business_id, customer_user_id, total_estimate, currency")
      .maybeSingle()

    if (!r1.error || !isColumnMissingError(r1.error, "total_estimate")) return r1

    // Backward-compat (older schema): `total_amount`.
    return await base
      .select("id, business_id, customer_user_id, total_amount, currency")
      .maybeSingle()
  })()

  if (reqErr || !reqRow) {
    return json(400, { error: "Invalid request" })
  }

  const isCustomer = reqRow.customer_user_id === user.id

  let isStaff = false
  if (!isCustomer) {
    const { data: member, error: mErr } = await sb
      .from("business_members")
      .select("role")
      .eq("business_id", reqRow.business_id)
      .eq("user_id", user.id)
      .maybeSingle()

    if (!mErr && member) {
      isStaff = ["owner", "admin", "staff"].includes((member as { role?: string }).role ?? "")
    }

    if (!isStaff) {
      return json(403, { error: "Forbidden" })
    }
  }

  const reqAmount =
    (reqRow as { total_estimate?: number; total_amount?: number }).total_estimate ??
    (reqRow as { total_amount?: number }).total_amount

  let payAmount = reqAmount
  if (isStaff && typeof amount === "number") {
    payAmount = amount
  } else if (amount != null && typeof amount !== "number") {
    return json(400, { error: "amount must be a number" })
  }

  if (typeof payAmount !== "number" || !Number.isFinite(payAmount) || payAmount <= 0) {
    return json(400, { error: "Invalid amount" })
  }

  const { data: intent, error: iErr } = await sb
    .from("payment_intents")
    .insert({
      business_id: reqRow.business_id,
      request_id,
      amount: payAmount,
      currency: reqRow.currency ?? "XOF",
      provider,
      status: "pending",
      created_by: user.id,
    })
    .select()
    .single()

  if (iErr) throw iErr

  if (!publicBaseUrl) {
    await sb.from("payment_intents")
      .update({ status: "failed", metadata: { error: "PUBLIC_BASE_URL missing" } })
      .eq("id", intent.id)

    return json(500, { error: "Payment provider not configured" })
  }

  const callbackUrl = `${publicBaseUrl}/payments_callback`

  let paymentUrl: string
  try {
    paymentUrl = await PayDunya.createCheckout({
      amount: payAmount,
      description: "Commande PME_TPE",
      reference: intent.id,
      callbackUrl,
    })
  } catch (e) {
    const msg = (e as { message?: unknown })?.message
    const safeMsg = typeof msg === "string" ? msg : "PayDunya error"
    console.error("create_payment_intent: paydunya failure", safeMsg)

    await sb.from("payment_intents")
      .update({ status: "failed", metadata: { error: safeMsg } })
      .eq("id", intent.id)

    return json(502, { error: "Paiement indisponible. Réessaie dans un instant." })
  }

  const { error: updErr } = await sb.from("payment_intents")
    .update({ external_ref: paymentUrl, status: "initiated" })
    .eq("id", intent.id)

  // Backward-compat: if `initiated` is not part of the enum, keep `pending`.
  if (updErr) {
    await sb.from("payment_intents")
      .update({ external_ref: paymentUrl })
      .eq("id", intent.id)
  }

  return json(200, { payment_url: paymentUrl })
})
