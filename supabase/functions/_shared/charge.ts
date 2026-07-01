// The shared charge pipeline used by both charge-walk and charge-stay. Given a
// validated, priced service, it: enforces card-on-file, runs the off-session
// charge through the active rail, records the ledger + a receipt on success, or
// records a failure + dunning + a Firestore failure signal on failure. Idempotent
// on `walkKey` (the walk id / stay key).
import { SupabaseClient } from "@supabase/supabase-js";
import { json } from "./cors.ts";
import { getProvider } from "./provider.ts";
import { computeFeeSplit, computeVat } from "./billing.ts";
import { getDefaultCard } from "./cards.ts";
import { addDoc, createDoc, patchDoc, serverTimestamp } from "./firestore.ts";

const RETRY_BACKOFF_MIN = 60; // first dunning retry ~1h out

export interface RunChargeOpts {
  db: SupabaseClient;
  uid: string;
  walkKey: string;
  chatId: string;
  postId: string;
  ownerId: string;
  sitterId: string;
  ownerName: string;
  amountAgorot: number;
  serviceDay: string;
  description: string; // provider-side description
  successText: string; // Hebrew chat/receipt text on success
  zeroText?: string; // Hebrew text when amount is 0 (e.g. walk included in daily rate)
  receiptEmail?: string;
  paymentDocExtra?: Record<string, unknown>;
  chatMessageExtra?: Record<string, unknown>;
  chatPatchExtra?: Record<string, unknown>;
}

export async function runCharge(o: RunChargeOpts): Promise<Response> {
  const { db, uid, walkKey } = o;

  // Idempotency: a settled charge for this walk/stay already exists.
  const existing = await db
    .from("transactions")
    .select("*")
    .eq("walk_id", walkKey)
    .eq("kind", "charge")
    .maybeSingle();
  if (existing.data?.status === "succeeded") {
    return json({ transaction: existing.data, idempotent: true }, 200);
  }

  const { platformFeeAgorot, sitterAccruedAgorot } = computeFeeSplit(o.amountAgorot);
  const { vatAgorot, vatRateBps } = computeVat(o.amountAgorot);
  const provider = getProvider();

  // Zero-rate (e.g. a walk included in the overnight daily rate): record the
  // succeeded transaction with no rail so the service is marked processed.
  if (o.amountAgorot <= 0) {
    return await recordSuccess(o, provider.name, "zero_rate", null, null, vatAgorot, vatRateBps, sitterAccruedAgorot, platformFeeAgorot, true);
  }

  // Card-on-file is required before a booking is approved; if it's somehow
  // missing at charge time, fail into dunning rather than silently skipping.
  const card = await getDefaultCard(db, o.ownerId, provider.name);
  if (!card) {
    return await recordFailure(o, provider.name, existing.data?.id, "no_card_on_file", null, null, null,
      platformFeeAgorot, sitterAccruedAgorot, vatAgorot, vatRateBps, false);
  }

  await db.from("payment_events").insert({
    kind: "charge_attempt",
    walk_id: walkKey,
    actor_uid: uid,
    payload: { amountAgorot: o.amountAgorot, platformFeeAgorot, vatAgorot },
  });

  const result = await provider.chargeByToken({
    amountAgorot: o.amountAgorot,
    currency: "ILS",
    customerId: card.customer_id ?? "",
    providerToken: card.provider_token,
    ownerId: o.ownerId,
    sitterId: o.sitterId,
    idempotencyKey: walkKey,
    description: o.description,
    receiptEmail: o.receiptEmail,
  });

  if (result.status !== "succeeded") {
    const requiresAction = result.status === "requires_action";
    return await recordFailure(
      o, provider.name, existing.data?.id, result.failureReason ?? result.status,
      result.providerRef, card.customer_id, card.provider_token,
      platformFeeAgorot, sitterAccruedAgorot, vatAgorot, vatRateBps, requiresAction,
    );
  }

  return await recordSuccess(
    o, provider.name, result.providerRef, card.customer_id, card.provider_token,
    vatAgorot, vatRateBps, sitterAccruedAgorot, platformFeeAgorot, false,
  );
}

// --- success ---------------------------------------------------------------------
async function recordSuccess(
  o: RunChargeOpts,
  providerName: string,
  providerRef: string,
  customerRef: string | null,
  paymentMethod: string | null,
  vatAgorot: number,
  vatRateBps: number,
  sitterAccruedAgorot: number,
  platformFeeAgorot: number,
  zeroRate: boolean,
): Promise<Response> {
  const recorded = await o.db.rpc("record_walk_charge", {
    p_walk_id: o.walkKey, p_chat_id: o.chatId, p_post_id: o.postId, p_owner_id: o.ownerId,
    p_sitter_id: o.sitterId, p_amount_agorot: o.amountAgorot, p_currency: "ILS",
    p_provider: providerName, p_provider_ref: providerRef, p_service_day: o.serviceDay,
    p_platform_fee_agorot: platformFeeAgorot, p_sitter_accrued_agorot: sitterAccruedAgorot,
    p_vat_agorot: vatAgorot, p_vat_rate_bps: vatRateBps,
    p_customer_ref: customerRef, p_provider_payment_method: paymentMethod,
  });
  if (recorded.error) {
    // Unique-violation race: another call recorded it first — return that one.
    const again = await o.db.from("transactions").select("*").eq("walk_id", o.walkKey).eq("kind", "charge").maybeSingle();
    if (again.data) return json({ transaction: again.data, idempotent: true }, 200);
    throw new Error(recorded.error.message);
  }
  const tx = recorded.data as Record<string, unknown>;
  const txId = String(tx.id);

  // Receipt (VAT breakdown). Best-effort — never block the charge on receipting.
  await o.db.from("receipts").insert({
    transaction_id: txId,
    net_agorot: o.amountAgorot - vatAgorot,
    vat_agorot: vatAgorot,
    gross_agorot: o.amountAgorot,
    vat_rate_bps: vatRateBps,
    owner_id: o.ownerId,
    sitter_id: o.sitterId,
  }).then(undefined, () => {});

  const message = zeroRate && o.zeroText ? o.zeroText : o.successText;

  await createDoc("payments", txId, {
    ...(o.paymentDocExtra ?? {}),
    transactionId: txId,
    chatId: o.chatId, postId: o.postId, ownerId: o.ownerId, sitterId: o.sitterId,
    amountAgorot: o.amountAgorot, currency: "ILS", status: "succeeded",
    provider: providerName, text: message, createdAt: serverTimestamp(),
  });

  await addDoc(`chats/${o.chatId}/messages`, {
    senderId: o.ownerId,
    senderName: o.ownerName,
    text: message,
    type: "payment",
    ...(o.chatMessageExtra ?? {}),
    amountAgorot: o.amountAgorot,
    paymentStatus: "succeeded",
    createdAt: serverTimestamp(),
  });

  await patchDoc(`chats/${o.chatId}`, {
    lastMessage: message,
    lastMessageTime: serverTimestamp(),
    lastMessageSenderId: o.ownerId,
    ...(o.chatPatchExtra ?? {}),
  });

  await o.db.from("payment_events").insert({
    kind: "charge_succeeded", walk_id: o.walkKey, actor_uid: o.uid,
    payload: { txId, amountAgorot: o.amountAgorot },
  });

  return json({ transaction: tx }, 200);
}

// --- failure (+ dunning + Firestore signal) --------------------------------------
async function recordFailure(
  o: RunChargeOpts,
  providerName: string,
  existingId: string | undefined,
  reason: string,
  providerRef: string | null,
  customerRef: string | null,
  paymentMethod: string | null,
  platformFeeAgorot: number,
  sitterAccruedAgorot: number,
  vatAgorot: number,
  vatRateBps: number,
  requiresAction: boolean,
): Promise<Response> {
  const nextRetry = new Date(Date.now() + RETRY_BACKOFF_MIN * 60_000).toISOString();
  const row = {
    walk_id: o.walkKey, chat_id: o.chatId, post_id: o.postId, owner_id: o.ownerId,
    sitter_id: o.sitterId, amount_agorot: o.amountAgorot, status: "failed", kind: "charge",
    provider: providerName, provider_ref: providerRef, service_day: o.serviceDay,
    platform_fee_agorot: platformFeeAgorot, sitter_accrued_agorot: sitterAccruedAgorot,
    vat_agorot: vatAgorot, vat_rate_bps: vatRateBps,
    customer_ref: customerRef, provider_payment_method: paymentMethod,
    last_failure_reason: reason, dunning_state: "retrying", next_retry_at: nextRetry,
  };

  // One charge row per walk: update the prior pending/failed row, else insert.
  let txId: string | undefined;
  if (existingId) {
    const upd = await o.db.from("transactions").update(row).eq("id", existingId).select("id").maybeSingle();
    txId = upd.data?.id;
  } else {
    const ins = await o.db.from("transactions").insert(row).select("id").maybeSingle();
    txId = ins.data?.id;
  }

  await o.db.from("payment_events").insert({
    kind: "charge_failed", walk_id: o.walkKey, actor_uid: o.uid,
    payload: { reason, requiresAction },
  });

  // Firestore failure signal so the owner's wallet + chat reflect it and the
  // client can fire a local alert (no backend push yet — see Phase 4).
  const message = requiresAction
    ? "נדרש אימות לתשלום — יש לאשר מחדש את התשלום"
    : reason === "no_card_on_file"
    ? "התשלום לא בוצע — נא להוסיף אמצעי תשלום"
    : "התשלום נכשל — נא לעדכן את אמצעי התשלום";

  if (txId) {
    await createDoc("payments", txId, {
      ...(o.paymentDocExtra ?? {}),
      transactionId: txId,
      chatId: o.chatId, postId: o.postId, ownerId: o.ownerId, sitterId: o.sitterId,
      amountAgorot: o.amountAgorot, currency: "ILS", status: "failed",
      provider: providerName, text: message,
      requiresAction, failureReason: reason,
      createdAt: serverTimestamp(),
    });
  }

  await addDoc(`chats/${o.chatId}/messages`, {
    senderId: o.ownerId,
    senderName: o.ownerName,
    text: message,
    type: "payment",
    ...(o.chatMessageExtra ?? {}),
    amountAgorot: o.amountAgorot,
    paymentStatus: "failed",
    createdAt: serverTimestamp(),
  });

  return json({ error: "payment failed", reason, requiresAction }, 402);
}
