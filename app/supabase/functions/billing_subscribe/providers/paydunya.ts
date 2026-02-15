export interface PayDunyaCheckoutParams {
  amount: number;
  description: string;
  reference: string;
  callbackUrl: string;
  returnUrl?: string;
  cancelUrl?: string;
}

export class PayDunya {
  static async createCheckout(params: PayDunyaCheckoutParams): Promise<string> {
    const apiKey = Deno.env.get("PAYDUNYA_API_KEY");
    const apiSecret = Deno.env.get("PAYDUNYA_API_SECRET");
    const masterKey = Deno.env.get("PAYDUNYA_MASTER_KEY");

    if (!apiKey || !apiSecret || !masterKey) {
      throw new Error("PayDunya env keys missing");
    }

    const payload = {
      invoice: {
        total_amount: params.amount,
        description: params.description,
      },
      store: {
        name: "PME_TPE",
      },
      actions: {
        callback_url: params.callbackUrl,
        return_url: params.returnUrl ?? params.callbackUrl,
        cancel_url: params.cancelUrl ?? params.callbackUrl,
      },
      custom_data: {
        reference: params.reference,
      },
    };

    const res = await fetch("https://app.paydunya.com/api/v1/checkout-invoice/create", {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "PAYDUNYA-MASTER-KEY": masterKey,
        "PAYDUNYA-PRIVATE-KEY": apiSecret,
        "PAYDUNYA-PUBLIC-KEY": apiKey,
      },
      body: JSON.stringify(payload),
    });

    const text = await res.text();
    let json: any = null;
    try {
      json = JSON.parse(text);
    } catch {
      throw new Error(`PayDunya non-JSON response (${res.status}): ${text.slice(0, 600)}`);
    }

    if (!res.ok || !json?.response_code || json.response_code !== "00") {
      throw new Error(`PayDunya error (${res.status}): ${JSON.stringify(json).slice(0, 1200)}`);
    }

    if (!json.response_text || typeof json.response_text !== "string") {
      throw new Error(`PayDunya missing response_text (${res.status}): ${JSON.stringify(json).slice(0, 1200)}`);
    }

    return json.response_text; // URL de paiement
  }
}
