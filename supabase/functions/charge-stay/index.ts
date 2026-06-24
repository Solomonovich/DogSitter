// POST /charge-stay   body: { "chatId": "<id>" }
//
// Charges an OVERNIGHT stay once, at end of stay: nights × per-night rate. Called by
// the iOS app when the sitter taps "End stay". Idempotent on a synthetic walk id
// `stay_<chatId>` so tapping twice never double-charges.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { addDoc, createDoc, getDoc, patchDoc, serverTimestamp } from "../_shared/firestore.ts";
import { getProvider } from "../_shared/provider.ts";
import { computeNights, computeStayChargeAgorot, formatIls, mappedPostType, serviceDayString } from "../_shared/billing.ts";
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

  const { chatId } = await req.json().catch(() => ({}));
  if (!chatId || typeof chatId !== "string") return json({ error: "chatId required" }, 400);

  const db = serviceClient();

  try {
    const chat = await getDoc(`chats/${chatId}`);
    if (!chat) return json({ error: "chat not found" }, 404);
    if (chat.approved !== true) return json({ error: "booking not approved" }, 409);

    const ownerId = String(chat.ownerId ?? "");
    const sitterId = String(chat.sitterId ?? "");
    if (uid !== ownerId && uid !== sitterId) return json({ error: "forbidden" }, 403);

    const postId = String(chat.postId ?? "");
    const post = await getDoc(`posts/${postId}`);
    if (!post) return json({ error: "post not found" }, 404);
    if (mappedPostType(post) !== "overnight") return json({ error: "not an overnight post" }, 409);

    const perNight = Number(post.payAmount ?? 0);
    if (!(perNight > 0)) return json({ error: "post has no valid price" }, 422);

    // Idempotency: one charge per stay (per chat).
    const stayKey = `stay_${chatId}`;
    const existing = await db.from("transactions").select("*").eq("walk_id", stayKey).maybeSingle();
    if (existing.data) return json({ transaction: existing.data, idempotent: true }, 200);

    const nights = computeNights(post.startDate as string | undefined, post.endDate as string | undefined);
    const amountAgorot = computeStayChargeAgorot(perNight, nights);
    const serviceDay = serviceDayString(post.endDate as string | undefined);

    await db.from("payment_events").insert({
      kind: "stay_charge_attempt", walk_id: stayKey, actor_uid: uid,
      payload: { nights, perNight, amountAgorot },
    });

    const provider = getProvider();
    const result = await provider.charge({
      amountAgorot, currency: "ILS", ownerId, sitterId, walkId: stayKey, idempotencyKey: stayKey,
    });
    if (result.status === "failed") {
      await db.from("transactions").insert({
        walk_id: stayKey, chat_id: chatId, post_id: postId, owner_id: ownerId,
        sitter_id: sitterId, amount_agorot: amountAgorot, status: "failed",
        provider: provider.name, service_day: serviceDay,
      });
      await db.from("payment_events").insert({
        kind: "stay_charge_failed", walk_id: stayKey, actor_uid: uid,
        payload: { reason: result.failureReason },
      });
      return json({ error: "payment failed", reason: result.failureReason }, 402);
    }

    const recorded = await db.rpc("record_walk_charge", {
      p_walk_id: stayKey, p_chat_id: chatId, p_post_id: postId, p_owner_id: ownerId,
      p_sitter_id: sitterId, p_amount_agorot: amountAgorot, p_currency: "ILS",
      p_provider: provider.name, p_provider_ref: result.providerRef, p_service_day: serviceDay,
    });
    if (recorded.error) {
      const again = await db.from("transactions").select("*").eq("walk_id", stayKey).maybeSingle();
      if (again.data) return json({ transaction: again.data, idempotent: true }, 200);
      throw new Error(recorded.error.message);
    }
    const tx = recorded.data as Record<string, unknown>;
    const txId = String(tx.id);

    const nightWord = nights === 1 ? "לילה" : "לילות";
    const message = `תשלום עבור ${nights} ${nightWord}: ${formatIls(amountAgorot)} ✓`;

    await createDoc("payments", txId, {
      transactionId: txId,
      walkId: stayKey, chatId, postId, ownerId, sitterId,
      amountAgorot, currency: "ILS", status: "succeeded",
      provider: provider.name, text: message,
      createdAt: serverTimestamp(),
    });

    await addDoc(`chats/${chatId}/messages`, {
      senderId: ownerId,
      senderName: String(chat.ownerName ?? ""),
      text: message,
      type: "payment",
      amountAgorot,
      paymentStatus: "succeeded",
      createdAt: serverTimestamp(),
    });

    await patchDoc(`chats/${chatId}`, {
      lastMessage: message,
      lastMessageTime: serverTimestamp(),
      lastMessageSenderId: ownerId,
      stayCompletedAt: serverTimestamp(),
    });

    await db.from("payment_events").insert({
      kind: "stay_charge_succeeded", walk_id: stayKey, actor_uid: uid,
      payload: { txId, nights, amountAgorot },
    });

    return json({ transaction: tx, nights }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
