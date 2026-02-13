import { serve } from "https://deno.land/std@0.192.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"
import { PayDunya } from "./providers/paydunya.ts"

serve(async (req) => {
  const { business_id, plan_code } = await req.json()
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  const { data: plan } = await sb
    .from("plans")
    .select()
    .eq("code", plan_code)
    .single()

  if (!plan) return new Response("Plan inconnu", { status: 400 })

  const paymentUrl = await PayDunya.createCheckout({
    amount: plan.monthly_price_amount,
    description: `Abonnement ${plan.name}`,
    reference: crypto.randomUUID(),
    callbackUrl: `${Deno.env.get("PUBLIC_BASE_URL")}/payments_callback`,
  })

  await sb.from("subscriptions").insert({
    business_id,
    provider: "PAYDUNYA",
    status: "pending",
    provider_customer_id: "pme_tpe_user",
    provider_subscription_id: plan_code,
  })

  return new Response(JSON.stringify({ payment_url: paymentUrl }), {
    headers: { "Content-Type": "application/json" },
  })
})
