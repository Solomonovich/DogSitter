// POST /retry-charges   header: x-cron-secret: <CRON_SECRET>
//
// Dunning runner (invoked on a schedule by Supabase cron). Re-attempts charges in
// `dunning_state='retrying'` whose `next_retry_at` has passed, with exponential
// backoff, escalating to `failed_final` after MAX_RETRIES. Authenticated by a cron
// secret (not a Firebase token).
import { SupabaseClient } from "@supabase/supabase-js";
import { json, preflight } from "../_shared/cors.ts";
import { getProvider } from "../_shared/provider.ts";
import { getDefaultCard } from "../_shared/cards.ts";
import { addDoc, patchDoc, serverTimestamp } from "../_shared/firestore.ts";
import { formatIls } from "../_shared/billing.ts";
import { serviceClient } from "../_shared/db.ts";

const MAX_RETRIES = 4;
const BACKOFF_MIN = [60, 360, 1440, 4320]; // 1h, 6h, 24h, 72h
const BATCH = 25;

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "forbidden" }, 403);
  }

  const db = serviceClient();
  const due = await db.from("transactions").select("*")
    .eq("kind", "charge").eq("dunning_state", "retrying")
    .lte("next_retry_at", new Date().toISOString())
    .limit(BATCH);
  if (due.error) return json({ error: due.error.message }, 500);

  const provider = getProvider();
  let succeeded = 0, retried = 0, exhausted = 0;

  for (const tx of (due.data ?? []) as Record<string, unknown>[]) {
    const ownerId = String(tx.owner_id);
    const card = await getDefaultCard(db, ownerId, provider.name);
    if (!card) { (await bump(db, tx, "no_card_on_file")) ? exhausted++ : retried++; continue; }

    const result = await provider.chargeByToken({
      amountAgorot: Number(tx.amount_agorot),
      currency: String(tx.currency ?? "ILS"),
      customerId: card.customer_id ?? "",
      providerToken: card.provider_token,
      ownerId,
      sitterId: String(tx.sitter_id),
      idempotencyKey: String(tx.walk_id),
    });

    if (result.status === "succeeded") {
      await db.rpc("settle_transaction", {
        p_walk_id: String(tx.walk_id), p_status: "succeeded", p_provider_ref: result.providerRef,
      });
      // Reconcile the Firestore failure signal the owner saw earlier.
      const msg = `התשלום בוצע: ${formatIls(Number(tx.amount_agorot))} ✓`;
      await patchDoc(`payments/${tx.id}`, { status: "succeeded", text: msg, requiresAction: false }).catch(() => {});
      await addDoc(`chats/${tx.chat_id}/messages`, {
        senderId: ownerId, text: msg, type: "payment",
        amountAgorot: Number(tx.amount_agorot), paymentStatus: "succeeded", createdAt: serverTimestamp(),
      }).catch(() => {});
      succeeded++;
    } else {
      (await bump(db, tx, result.failureReason ?? result.status)) ? exhausted++ : retried++;
    }
  }

  return json({ processed: (due.data ?? []).length, succeeded, retried, exhausted }, 200);
});

/** Advance retry state; returns true when the charge is exhausted (failed_final). */
async function bump(db: SupabaseClient, tx: Record<string, unknown>, reason: string): Promise<boolean> {
  const next = Number(tx.retry_count ?? 0) + 1;
  if (next >= MAX_RETRIES) {
    await db.from("transactions").update({
      retry_count: next, dunning_state: "failed_final", last_failure_reason: reason,
    }).eq("id", tx.id);
    return true;
  }
  const mins = BACKOFF_MIN[Math.min(next, BACKOFF_MIN.length - 1)];
  await db.from("transactions").update({
    retry_count: next, last_failure_reason: reason,
    next_retry_at: new Date(Date.now() + mins * 60_000).toISOString(),
  }).eq("id", tx.id);
  return false;
}
