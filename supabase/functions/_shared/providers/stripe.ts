// Stripe rail. Talks to the Stripe REST API directly over fetch (no SDK) to keep
// the edge runtime light. Cards are captured client-side via PaymentSheet (a
// SetupIntent); charges are off-session PaymentIntents by the saved payment method.
//
// ILS note: Stripe amounts are in the currency's minor unit; for ILS that minor
// unit IS the agorot, so amountAgorot maps straight to Stripe's `amount`.
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

const STRIPE_API = "https://api.stripe.com";
// MUST equal the iOS SDK's STPAPIClient.apiVersion (StripeCore pins "2020-08-27").
// The SDK uses the ephemeral key with THIS version, so a mismatch makes PaymentSheet
// fail to load the customer (endless spinner / stuck sheet). The client also sends
// its version; this is the safe default if it doesn't.
const STRIPE_API_VERSION = "2020-08-27";

function secretKey(): string {
  const k = Deno.env.get("STRIPE_SECRET_KEY");
  if (!k) throw new Error("STRIPE_SECRET_KEY unset");
  return k;
}

/** Form-encode a (possibly nested) object using Stripe's bracket notation. */
function encodeForm(obj: Record<string, unknown>, prefix = ""): string {
  const parts: string[] = [];
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    const key = prefix ? `${prefix}[${k}]` : k;
    if (typeof v === "object" && !Array.isArray(v)) {
      parts.push(encodeForm(v as Record<string, unknown>, key));
    } else {
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(v))}`);
    }
  }
  return parts.filter(Boolean).join("&");
}

interface StripeResponse {
  ok: boolean;
  status: number;
  data: Record<string, unknown>;
}

async function stripe(
  method: "GET" | "POST",
  path: string,
  params?: Record<string, unknown>,
  opts?: { idempotencyKey?: string; apiVersion?: string },
): Promise<StripeResponse> {
  const headers: Record<string, string> = {
    authorization: `Bearer ${secretKey()}`,
    "content-type": "application/x-www-form-urlencoded",
  };
  if (opts?.idempotencyKey) headers["Idempotency-Key"] = opts.idempotencyKey;
  if (opts?.apiVersion) headers["Stripe-Version"] = opts.apiVersion;

  let url = `${STRIPE_API}${path}`;
  const body = params ? encodeForm(params) : undefined;
  if (method === "GET" && body) url += `?${body}`;

  const res = await fetch(url, {
    method,
    headers,
    body: method === "POST" ? body : undefined,
  });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

export class StripeProvider implements PaymentProvider {
  readonly name = "stripe" as const;

  async createCustomer(input: CreateCustomerInput): Promise<{ customerId: string }> {
    const res = await stripe("POST", "/v1/customers", {
      email: input.email,
      metadata: { uid: input.uid },
    });
    if (!res.ok) throw new Error(`stripe createCustomer: ${stringifyErr(res)}`);
    return { customerId: String(res.data.id) };
  }

  async createSetupSession(input: SetupSessionInput): Promise<SetupSession> {
    // Ephemeral key lets the iOS PaymentSheet act on the customer's behalf. It MUST
    // be created with the SDK's own API version (passed by the client) — a mismatch
    // makes PaymentSheet hang loading the customer.
    const ek = await stripe("POST", "/v1/ephemeral_keys", { customer: input.customerId }, {
      apiVersion: input.apiVersion ?? STRIPE_API_VERSION,
    });
    if (!ek.ok) throw new Error(`stripe ephemeral_key: ${stringifyErr(ek)}`);

    // Card-only. `automatic_payment_methods` pulls in every method enabled on the
    // account (Link, Bancontact, …) — PaymentSheet can't offer several of them for
    // off-session setup (and delayed methods can't be charged off-session anyway),
    // which makes PaymentSheet fail to present and the flow hang. We only ever
    // charge a saved card off-session, so restrict the SetupIntent to card.
    const si = await stripe("POST", "/v1/setup_intents", {
      customer: input.customerId,
      usage: "off_session",
      "payment_method_types[0]": "card",
    });
    if (!si.ok) throw new Error(`stripe setup_intent: ${stringifyErr(si)}`);

    return {
      kind: "stripe_setup_intent",
      customerId: input.customerId,
      setupIntentClientSecret: String(si.data.client_secret),
      ephemeralKeySecret: String(ek.data.secret),
      publishableKey: Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? "",
    };
  }

  async finalizeSavedCard(
    input: { uid: string; customerId: string; ref: string },
  ): Promise<SavedCard> {
    let pmId = input.ref;

    // `ref` may be a SetupIntent (seti_…) — resolve it to its payment method.
    if (pmId.startsWith("seti_")) {
      const si = await stripe("GET", `/v1/setup_intents/${pmId}`);
      if (!si.ok) throw new Error(`stripe retrieve setup_intent: ${stringifyErr(si)}`);
      pmId = String(si.data.payment_method ?? "");
    }

    // Fallback: no ref — take the customer's most recent card.
    if (!pmId || !pmId.startsWith("pm_")) {
      const list = await stripe("GET", `/v1/customers/${input.customerId}/payment_methods`, {
        type: "card",
        limit: 1,
      });
      const first = (list.data.data as Record<string, unknown>[] | undefined)?.[0];
      if (!first) throw new Error("stripe finalizeSavedCard: no card found");
      pmId = String(first.id);
    }

    const pm = await stripe("GET", `/v1/payment_methods/${pmId}`);
    if (!pm.ok) throw new Error(`stripe retrieve payment_method: ${stringifyErr(pm)}`);
    const card = (pm.data.card ?? {}) as Record<string, unknown>;

    // Make it the customer's default so off-session charges use it.
    await stripe("POST", `/v1/customers/${input.customerId}`, {
      invoice_settings: { default_payment_method: pmId },
    });

    return {
      providerToken: pmId,
      customerId: input.customerId,
      brand: String(card.brand ?? "card"),
      last4: String(card.last4 ?? "????"),
      expMonth: card.exp_month ? Number(card.exp_month) : undefined,
      expYear: card.exp_year ? Number(card.exp_year) : undefined,
    };
  }

  async chargeByToken(req: ChargeByTokenRequest): Promise<ChargeResult> {
    const res = await stripe("POST", "/v1/payment_intents", {
      amount: req.amountAgorot,
      currency: req.currency.toLowerCase(),
      customer: req.customerId,
      payment_method: req.providerToken,
      off_session: true,
      confirm: true,
      description: req.description,
      receipt_email: req.receiptEmail,
      metadata: {
        walkId: req.idempotencyKey,
        ownerId: req.ownerId,
        sitterId: req.sitterId,
      },
    }, { idempotencyKey: req.idempotencyKey });

    // Off-session auth required (common on Israeli cards): owner must re-confirm.
    const err = res.data.error as Record<string, unknown> | undefined;
    if (err) {
      const code = String(err.code ?? "");
      const pi = err.payment_intent as Record<string, unknown> | undefined;
      if (code === "authentication_required") {
        return { status: "requires_action", providerRef: String(pi?.id ?? ""), failureReason: code };
      }
      return { status: "failed", providerRef: String(pi?.id ?? ""), failureReason: String(err.message ?? code) };
    }

    const status = String(res.data.status ?? "");
    if (status === "succeeded") return { status: "succeeded", providerRef: String(res.data.id) };
    if (status === "requires_action" || status === "requires_confirmation") {
      return { status: "requires_action", providerRef: String(res.data.id) };
    }
    return { status: "failed", providerRef: String(res.data.id ?? ""), failureReason: status || "unknown" };
  }

  async refund(
    req: { providerRef: string; amountAgorot?: number; idempotencyKey: string },
  ): Promise<RefundResult> {
    const res = await stripe("POST", "/v1/refunds", {
      payment_intent: req.providerRef,
      amount: req.amountAgorot,
    }, { idempotencyKey: req.idempotencyKey });
    if (!res.ok) {
      const err = res.data.error as Record<string, unknown> | undefined;
      return { status: "failed", providerRef: "", failureReason: String(err?.message ?? "refund failed") };
    }
    const status = String(res.data.status ?? "");
    return {
      status: status === "succeeded" || status === "pending" ? "succeeded" : "failed",
      providerRef: String(res.data.id),
      failureReason: status === "failed" ? "refund failed" : undefined,
    };
  }

  async verifyAndParseWebhook(req: Request, rawBody: string): Promise<WebhookEvent | null> {
    const sig = req.headers.get("stripe-signature");
    const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
    if (!sig || !secret) return null;
    if (!(await verifyStripeSignature(sig, rawBody, secret))) return null;

    const event = JSON.parse(rawBody) as Record<string, unknown>;
    const obj = ((event.data as Record<string, unknown>)?.object ?? {}) as Record<string, unknown>;
    const meta = (obj.metadata ?? {}) as Record<string, unknown>;
    const typeMap: Record<string, WebhookType> = {
      "payment_intent.succeeded": "charge_succeeded",
      "payment_intent.payment_failed": "charge_failed",
      "charge.refunded": "charge_refunded",
      "charge.dispute.created": "dispute_created",
      "setup_intent.succeeded": "setup_succeeded",
    };
    const type = typeMap[String(event.type)] ?? "unknown";

    return {
      type,
      eventId: String(event.id),
      providerRef: String(obj.payment_intent ?? obj.id ?? ""),
      idempotencyKey: meta.walkId ? String(meta.walkId) : undefined,
      amountAgorot: obj.amount != null ? Number(obj.amount) : undefined,
      raw: event,
    };
  }
}

function stringifyErr(res: StripeResponse): string {
  const err = res.data.error as Record<string, unknown> | undefined;
  return `${res.status} ${err?.message ?? JSON.stringify(res.data)}`;
}

/** Verify a `Stripe-Signature` header: HMAC-SHA256 of `${t}.${rawBody}`. */
async function verifyStripeSignature(header: string, rawBody: string, secret: string): Promise<boolean> {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => kv.split("=").map((s) => s.trim()) as [string, string]),
  );
  const t = parts["t"];
  const v1 = parts["v1"];
  if (!t || !v1) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${rawBody}`));
  const expected = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return timingSafeEqual(expected, v1);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}
