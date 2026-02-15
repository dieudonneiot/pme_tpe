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
    const publicKey = Deno.env.get("PAYDUNYA_API_KEY") ?? Deno.env.get("PAYDUNYA_PUBLIC_KEY");
    const privateKey = Deno.env.get("PAYDUNYA_API_SECRET") ?? Deno.env.get("PAYDUNYA_PRIVATE_KEY");
    const masterKey = Deno.env.get("PAYDUNYA_MASTER_KEY");
    const token = Deno.env.get("PAYDUNYA_TOKEN") ?? Deno.env.get("PAYDUNYA_API_TOKEN");

    if (!privateKey || !masterKey || !token) {
      throw new Error(
        "PayDunya env keys missing (need PAYDUNYA_MASTER_KEY + PAYDUNYA_API_SECRET/PRIVATE_KEY + PAYDUNYA_TOKEN)",
      );
    }

    const modeRaw = (Deno.env.get("PAYDUNYA_MODE") ?? "").toLowerCase();
    const mode =
      modeRaw === "test" || modeRaw === "sandbox"
        ? "test"
        : modeRaw === "live" || modeRaw === "prod" || modeRaw === "production"
          ? "live"
          : privateKey.startsWith("test_")
            ? "test"
            : "live";

    const endpoint = mode === "test"
      ? "https://app.paydunya.com/sandbox-api/v1/checkout-invoice/create"
      : "https://app.paydunya.com/api/v1/checkout-invoice/create";

    const payload = {
      invoice: {
        // XOF and most PayDunya flows expect integer amounts.
        total_amount: Math.round(params.amount),
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

    const headers: Record<string, string> = {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "PAYDUNYA-MASTER-KEY": masterKey,
      "PAYDUNYA-PRIVATE-KEY": privateKey,
      "PAYDUNYA-TOKEN": token,
    };

    // Some PayDunya setups also expose a public key; keep it best-effort.
    if (publicKey) headers["PAYDUNYA-PUBLIC-KEY"] = publicKey;

    const res = await fetch(endpoint, {
      method: "POST",
      headers,
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
