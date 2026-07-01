// POST /refund   body: { "transactionId": "<uuid>", "amountAgorot"?: number }
//
// Refunds a prior succeeded charge (full if amount omitted, else partial). Allowed
// for the charge's OWNER or a platform admin. Refunds the rail, records the ledger
// reversal (record_refund), and mirrors the refund to Firestore. Idempotent on the
// refund's idempotency key.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, isAdmin, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { providerByName } from "../_shared/provider.ts";
import { addDoc, createDoc, patchDoc, serverTimestamp } from "../_shared/firestore.ts";
import { formatIls } from "../_shared/billing.ts";
import { serviceClient } from "../_shared/db.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  let uid: string;
  try {
    ({ uid } = await verifyFirebaseToken(req));
  } catch (e) {
    return json({ error: (e as Error).message }, e instanceof AuthError ? 401 : 500);
  }

  const body = await req.json().catch(() => ({}));
  const transactionId = String(body.transactionId ?? "");
  if (!transactionId) return json({ error: "transactionId required" }, 400);

  const db = serviceClient();

  try {
    const { data: tx } = await db.from("transactions").select("*").eq("id", transactionId).maybeSingle();
    if (!tx) return json({ error: "transaction not found" }, 404);
    if (tx.kind !== "charge" || tx.status !== "succeeded") {
      return json({ error: "transaction is not a refundable charge" }, 409);
    }
    if (uid !== tx.owner_id && !isAdmin(uid)) return json({ error: "forbidden" }, 403);

    const amount = body.amountAgorot != null ? Number(body.amountAgorot) : Number(tx.amount_agorot);
    if (!(amount > 0) || amount > Number(tx.amount_agorot)) {
      return json({ error: "invalid refund amount" }, 422);
    }

    const provider = providerByName(String(tx.provider));
    const result = await provider.refund({
      providerRef: String(tx.provider_ref ?? ""),
      amountAgorot: amount,
      idempotencyKey: `refund_${tx.id}_${amount}`,
    });
    if (result.status !== "succeeded") {
      return json({ error: "refund failed", reason: result.failureReason }, 402);
    }

    const recorded = await db.rpc("record_refund", {
      p_parent_tx_id: tx.id,
      p_amount_agorot: amount,
      p_provider: String(tx.provider),
      p_provider_ref: result.providerRef,
    });
    if (recorded.error) throw new Error(recorded.error.message);
    const refund = recorded.data as Record<string, unknown>;
    const refundId = String(refund.id);

    // Mirror to Firestore so both parties see the refund.
    const message = `זוכה החזר: ${formatIls(amount)} ↩︎`;
    await createDoc("payments", refundId, {
      transactionId: refundId,
      walkId: tx.walk_id, chatId: tx.chat_id, postId: tx.post_id,
      ownerId: tx.owner_id, sitterId: tx.sitter_id,
      amountAgorot: amount, currency: "ILS", status: "refunded",
      kind: "refund", parentTransactionId: tx.id,
      provider: tx.provider, text: message, createdAt: serverTimestamp(),
    });
    await addDoc(`chats/${tx.chat_id}/messages`, {
      senderId: tx.owner_id,
      text: message,
      type: "payment",
      amountAgorot: amount,
      paymentStatus: "refunded",
      createdAt: serverTimestamp(),
    });
    await patchDoc(`chats/${tx.chat_id}`, {
      lastMessage: message,
      lastMessageTime: serverTimestamp(),
      lastMessageSenderId: tx.owner_id,
    });

    await db.from("payment_events").insert({
      kind: "refund_succeeded", walk_id: tx.walk_id, actor_uid: uid,
      payload: { refundId, parentTxId: tx.id, amount },
    });

    return json({ refund }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
