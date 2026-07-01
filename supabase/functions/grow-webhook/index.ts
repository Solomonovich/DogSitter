// POST /grow-webhook
//
// Receives Grow (Meshulam) IPN callbacks. Authenticated by the Grow shared-secret
// signature (NOT a Firebase token). Idempotent on (provider, event_id). Converges
// with the synchronous charge via settle_transaction.
import { json, preflight } from "../_shared/cors.ts";
import { GrowProvider } from "../_shared/providers/grow.ts";
import { serviceClient } from "../_shared/db.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const raw = await req.text();
  const provider = new GrowProvider();
  const event = await provider.verifyAndParseWebhook(req, raw);
  if (!event) return json({ error: "invalid signature" }, 400);

  const db = serviceClient();

  const dedupe = await db.from("webhook_events").insert({
    provider: "grow",
    event_id: event.eventId,
    type: event.type,
    payload: event.raw,
  });
  if (dedupe.error) return json({ ok: true, idempotent: true }, 200);

  try {
    switch (event.type) {
      case "charge_succeeded":
        if (event.idempotencyKey) {
          await db.rpc("settle_transaction", {
            p_walk_id: event.idempotencyKey, p_status: "succeeded", p_provider_ref: event.providerRef ?? null,
          });
        }
        break;
      case "charge_failed":
        if (event.idempotencyKey) {
          await db.rpc("settle_transaction", {
            p_walk_id: event.idempotencyKey, p_status: "failed",
            p_provider_ref: event.providerRef ?? null, p_failure_reason: "grow charge failed",
          });
        }
        break;
      default:
        await db.from("payment_events").insert({
          kind: `grow_${event.type}`,
          walk_id: event.idempotencyKey ?? null,
          payload: { eventId: event.eventId, providerRef: event.providerRef },
        });
    }
    return json({ ok: true }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
