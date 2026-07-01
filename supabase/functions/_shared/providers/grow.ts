// Grow by Meshulam rail (Israeli: cards + Bit + Apple Pay, hosted payment page,
// tokenization, refunds, IPN webhooks). Light API: https://grow-il.readme.io,
// https://doc.meshulam.co.il.
//
// ⚠️ VERIFY AGAINST YOUR GROW SANDBOX: the exact endpoint paths and field names
// below follow Grow's documented "Light API" shape, but Grow occasionally renames
// fields between accounts/versions. Confirm `sum` vs `paymentSum`, the token field
// on the IPN, and the refund endpoint with your sandbox before going live. The rail
// is wired and selectable (PAYMENT_PROVIDER=grow); these bodies are the finishing
// touches that need a live Grow account to validate.
import type {
  ChargeByTokenRequest,
  ChargeResult,
  CreateCustomerInput,
  PaymentProvider,
  RefundResult,
  SavedCard,
  SetupSession,
  SetupSessionInput,
  WebhookEvent,
  WebhookType,
} from "../provider.ts";

function base(): string {
  return Deno.env.get("GROW_BASE_URL") ?? "https://sandbox.meshulam.co.il";
}
function userId(): string {
  return Deno.env.get("GROW_USER_ID") ?? "";
}
function pageCode(): string {
  return Deno.env.get("GROW_PAGE_CODE") ?? "";
}
function apiKey(): string {
  return Deno.env.get("GROW_API_KEY") ?? "";
}

// Grow's Light API takes form-encoded params and returns { status, data }.
async function growPost(path: string, params: Record<string, unknown>): Promise<Record<string, unknown>> {
  const body = new URLSearchParams();
  body.set("userId", userId());
  body.set("apiKey", apiKey());
  for (const [k, v] of Object.entries(params)) if (v != null) body.set(k, String(v));
  const res = await fetch(`${base()}/api/light/server/1.0/${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const j = await res.json().catch(() => ({}));
  return j as Record<string, unknown>;
}

function ils(agorot: number): string {
  return (agorot / 100).toFixed(2); // Grow expects major-unit ILS
}

export class GrowProvider implements PaymentProvider {
  readonly name = "grow" as const;

  // Grow keys cards by token, not by a customer object; return a synthetic id so
  // the rest of the pipeline (which always passes a customerId) stays uniform.
  // deno-lint-ignore require-await
  async createCustomer(input: CreateCustomerInput): Promise<{ customerId: string }> {
    return { customerId: `grow_${input.uid}` };
  }

  // Open a hosted page that saves a card token (no charge). The token arrives via
  // the IPN / the return deep-link and is normalized in finalizeSavedCard.
  async createSetupSession(input: SetupSessionInput): Promise<SetupSession> {
    const r = await growPost("createPaymentProcess", {
      pageCode: pageCode(),
      sum: "1.00",                 // minimal verification amount (often refunded/J5)
      description: "שמירת אמצעי תשלום",
      chargeType: 4,               // 4 = save token only (verify code with Grow)
      saveCardToken: 1,
      successUrl: input.returnUrl,
      cancelUrl: input.returnUrl,
      cField1: input.uid,
    });
    const data = (r.data ?? {}) as Record<string, unknown>;
    if (!data.url) throw new Error(`grow createPaymentProcess failed: ${JSON.stringify(r)}`);
    return {
      kind: "grow_hosted_page",
      hostedPageUrl: String(data.url),
      processToken: String(data.processToken ?? data.processId ?? ""),
    };
  }

  // `ref` is the processId/processToken from the return; fetch the transaction to
  // read the saved card token + brand/last4.
  async finalizeSavedCard(
    input: { uid: string; customerId: string; ref: string },
  ): Promise<SavedCard> {
    const r = await growPost("getPaymentProcessInfo", { processToken: input.ref, processId: input.ref });
    const data = (r.data ?? {}) as Record<string, unknown>;
    const token = String(data.cardToken ?? data.token ?? "");
    if (!token) throw new Error(`grow finalizeSavedCard: no token (${JSON.stringify(r)})`);
    return {
      providerToken: token,
      customerId: input.customerId,
      brand: String(data.brandName ?? data.cardBrand ?? "card"),
      last4: String(data.last4Digits ?? data.cardSuffix ?? "????"),
    };
  }

  // Off-session charge by saved token (J4 direct debit). Idempotency: Grow dedups
  // on our `cField1` reference; we also guard with the ledger's unique walk index.
  async chargeByToken(req: ChargeByTokenRequest): Promise<ChargeResult> {
    const r = await growPost("directDebitPayment", {
      cardToken: req.providerToken,
      sum: ils(req.amountAgorot),
      description: req.description ?? "DogSitter",
      cField1: req.idempotencyKey,
    });
    const ok = Number(r.status) === 1;
    const data = (r.data ?? {}) as Record<string, unknown>;
    if (!ok) {
      return { status: "failed", providerRef: "", failureReason: String((r.err as Record<string, unknown>)?.message ?? r.status) };
    }
    return { status: "succeeded", providerRef: String(data.transactionId ?? data.transactionToken ?? "") };
  }

  async refund(
    req: { providerRef: string; amountAgorot?: number; idempotencyKey: string },
  ): Promise<RefundResult> {
    const r = await growPost("refundTransaction", {
      transactionId: req.providerRef,
      sum: req.amountAgorot != null ? ils(req.amountAgorot) : undefined,
    });
    const ok = Number(r.status) === 1;
    return ok
      ? { status: "succeeded", providerRef: String(((r.data ?? {}) as Record<string, unknown>).transactionId ?? req.providerRef) }
      : { status: "failed", providerRef: "", failureReason: String(r.status) };
  }

  // Grow IPN: verify the shared-secret signature, then normalize. Grow posts a
  // form body; the signature scheme varies by account — confirm with Grow.
  async verifyAndParseWebhook(req: Request, rawBody: string): Promise<WebhookEvent | null> {
    const secret = Deno.env.get("GROW_WEBHOOK_SECRET");
    if (!secret) return null;
    const params = new URLSearchParams(rawBody);
    // Grow sends the signature in a field (e.g. `signature`/`hash`); verify HMAC of
    // the raw body. VERIFY exact scheme with Grow before relying on it.
    const provided = params.get("signature") ?? params.get("hash") ?? "";
    const mac = await hmacHex(secret, rawBody.replace(/&?(signature|hash)=[^&]*/g, ""));
    if (!provided || !timingSafeEqual(mac, provided)) return null;

    const statusCode = params.get("status") ?? params.get("transactionTypeId") ?? "";
    const typeMap: Record<string, WebhookType> = {
      "1": "charge_succeeded",
      "success": "charge_succeeded",
      "error": "charge_failed",
      "refund": "charge_refunded",
    };
    const type = typeMap[statusCode] ?? "unknown";
    return {
      type,
      eventId: params.get("transactionId") ?? params.get("transactionToken") ?? crypto.randomUUID(),
      providerRef: params.get("transactionId") ?? undefined,
      idempotencyKey: params.get("cField1") ?? undefined,
      amountAgorot: params.get("sum") ? Math.round(Number(params.get("sum")) * 100) : undefined,
      raw: Object.fromEntries(params),
    };
  }
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}
