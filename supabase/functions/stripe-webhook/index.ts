// POST /stripe-webhook
//
// Receives Stripe events. Authenticated by the Stripe-Signature HMAC (NOT a
// Firebase token). Idempotent on (provider, event_id). Converges with the
// synchronous charge via settle_transaction (which accrues the ledger only on the
// transition into 'succeeded', so a sync success + this webhook never double-count).
import { json, preflight } from "../_shared/cors.ts";
import { StripeProvider } from "../_shared/providers/stripe.ts";
import { serviceClient } from "../_shared/db.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  // Must read the RAW body before parsing for HMAC verification.
  const raw = await req.text();
  const provider = new StripeProvider();
  const event = await provider.verifyAndParseWebhook(req, raw);
  if (!event) return json({ error: "invalid signature" }, 400);

  const db = serviceClient();

  // Idempotency: a re-delivered event is a no-op.
  const dedupe = await db.from("webhook_events").insert({
    provider: "stripe",
    event_id: event.eventId,
    type: event.type,
    payload: event.raw,
  });
  if (dedupe.error) {
    // Unique violation => already processed.
    return json({ ok: true, idempotent: true }, 200);
  }

  try {
    switch (event.type) {
      case "charge_succeeded":
        if (event.idempotencyKey) {
          await db.rpc("settle_transaction", {
            p_walk_id: event.idempotencyKey,
            p_status: "succeeded",
            p_provider_ref: event.providerRef ?? null,
          });
        }
        break;

      case "charge_failed":
        if (event.idempotencyKey) {
          await db.rpc("settle_transaction", {
            p_walk_id: event.idempotencyKey,
            p_status: "failed",
            p_provider_ref: event.providerRef ?? null,
            p_failure_reason: "stripe payment_failed",
          });
        }
        break;

      // Refunds initiated in-app are recorded synchronously by /refund; disputes
      // and out-of-band refunds are logged here for follow-up (Phase 4 alerting).
      case "charge_refunded":
      case "dispute_created":
      case "setup_succeeded":
      case "unknown":
        await db.from("payment_events").insert({
          kind: `stripe_${event.type}`,
          walk_id: event.idempotencyKey ?? null,
          payload: { eventId: event.eventId, providerRef: event.providerRef },
        });
        break;
    }
    return json({ ok: true }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
