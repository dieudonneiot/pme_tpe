import { serve } from "https://deno.land/std@0.192.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"

serve(async (req) => {
  const payload = await req.json()
  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  const { custom_data, status } = payload
  const ref = custom_data?.reference

  if (!ref) return new Response("Missing ref", { status: 400 })

  if (status === "completed" || status === "success") {
    await sb.rpc("apply_payment_reference", { ref })
  } else if (status === "failed") {
    await sb.from("payment_intents").update({ status: "failed" }).eq("id", ref)
  }

  return new Response("ok", { status: 200 })
})
