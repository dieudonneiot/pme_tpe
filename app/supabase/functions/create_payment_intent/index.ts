import { serve } from "https://deno.land/std@0.192.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"
import { PayDunya } from "./providers/paydunya.ts"

serve(async (req) => {
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  const { request_id, amount, provider } = await req.json()
  const auth = req.headers.get("Authorization")?.replace("Bearer ", "")
  const { data: user, error: authErr } = await sb.auth.getUser(auth)
  if (authErr || !user) return new Response("Unauthorized", { status: 401 })

  const { data: reqRow, error: reqErr } = await sb
    .from("service_requests")
    .select("id, business_id, total_amount, currency")
    .eq("id", request_id)
    .maybeSingle()

  if (reqErr || !reqRow)
    return new Response("Invalid request", { status: 400 })

  const payAmount = amount ?? reqRow.total_amount

  const { data: intent, error: iErr } = await sb
    .from("payment_intents")
    .insert({
      business_id: reqRow.business_id,
      amount: payAmount,
      currency: reqRow.currency ?? "XOF",
      provider,
      status: "pending",
      created_by: user.user.id,
    })
    .select()
    .single()

  if (iErr) throw iErr

  const callbackUrl = `${Deno.env.get("PUBLIC_BASE_URL")}/payments_callback`
  const paymentUrl = await PayDunya.createCheckout({
    amount: payAmount,
    description: "Commande PME_TPE",
    reference: intent.id,
    callbackUrl,
  })

  await sb.from("payment_intents")
    .update({ external_ref: paymentUrl, status: "initiated" })
    .eq("id", intent.id)

  return new Response(JSON.stringify({ payment_url: paymentUrl }), {
    headers: { "Content-Type": "application/json" },
  })
})
