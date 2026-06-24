// POST /charge-walk   body: { "walkId": "<id>" }
//
// Charges the owner for one completed walk and accrues the sitter's earnings
// (collect-only). Idempotent on walkId. Called by the iOS app from
// AppState.stopWalk() with the user's Firebase ID token.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { addDoc, createDoc, getDoc, patchDoc, serverTimestamp } from "../_shared/firestore.ts";
import { getProvider } from "../_shared/provider.ts";
import { computeWalkChargeAgorot, formatIls, mappedPostType, serviceDayString } from "../_shared/billing.ts";
import { serviceClient } from "../_shared/db.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  // 1. Auth ----------------------------------------------------------------------
  let uid: string;
  try {
    ({ uid } = await verifyFirebaseToken(req));
  } catch (e) {
    return json({ error: (e as Error).message }, e instanceof AuthError ? 401 : 500);
  }

  const { walkId } = await req.json().catch(() => ({}));
  if (!walkId || typeof walkId !== "string") return json({ error: "walkId required" }, 400);

  const db = serviceClient();

  try {
    // 2. Source-of-truth reads from Firestore ------------------------------------
    const walk = await getDoc(`walks/${walkId}`);
    if (!walk) return json({ error: "walk not found" }, 404);
    if (walk.status !== "completed") return json({ error: "walk not completed" }, 409);

    const ownerId = String(walk.ownerId ?? "");
    const sitterId = String(walk.sitterId ?? "");
    const chatId = String(walk.chatId ?? "");
    const postId = String(walk.postId ?? "");

    // 3. Caller must be a participant of this walk -------------------------------
    if (uid !== ownerId && uid !== sitterId) return json({ error: "forbidden" }, 403);

    const chat = await getDoc(`chats/${chatId}`);
    if (!chat) return json({ error: "chat not found" }, 404);
    if (chat.approved !== true) return json({ error: "booking not approved" }, 409);
    // Consistency: the walk's parties must match the chat's parties.
    if (chat.ownerId !== ownerId || chat.sitterId !== sitterId) {
      return json({ error: "walk/chat party mismatch" }, 409);
    }

    const post = await getDoc(`posts/${postId}`);
    if (!post) return json({ error: "post not found" }, 404);
    // Overnight walks are FREE — billing is per night (see charge-stay). Skip them.
    if (mappedPostType(post) === "overnight") {
      return json({ skipped: true, reason: "overnight walks are not billed" }, 200);
    }
    const payAmount = Number(post.payAmount ?? 0);
    if (!(payAmount > 0)) return json({ error: "post has no valid price" }, 422);

    // 4. Idempotency: already charged this walk? --------------------------------
    const existing = await db.from("transactions").select("*").eq("walk_id", walkId).maybeSingle();
    if (existing.data) return json({ transaction: existing.data, idempotent: true }, 200);

    // 5. Compute the amount — flat price per completed walk ---------------------
    const serviceDay = serviceDayString(walk.endTime as string | undefined);
    const amountAgorot = computeWalkChargeAgorot(payAmount);

    await db.from("payment_events").insert({
      kind: "charge_attempt",
      walk_id: walkId,
      actor_uid: uid,
      payload: { amountAgorot, payPer, serviceDay },
    });

    // 6. Run the (mock) rail. Zero-amount walks skip the rail but are still recorded
    //    so the walk is marked processed (idempotency).
    const provider = getProvider();
    let providerRef = "zero_rate";
    if (amountAgorot > 0) {
      const result = await provider.charge({
        amountAgorot,
        currency: "ILS",
        ownerId,
        sitterId,
        walkId,
        idempotencyKey: walkId,
      });
      if (result.status === "failed") {
        await db.from("transactions").insert({
          walk_id: walkId, chat_id: chatId, post_id: postId, owner_id: ownerId,
          sitter_id: sitterId, amount_agorot: amountAgorot, status: "failed",
          provider: provider.name, service_day: serviceDay,
        });
        await db.from("payment_events").insert({
          kind: "charge_failed", walk_id: walkId, actor_uid: uid,
          payload: { reason: result.failureReason },
        });
        return json({ error: "payment failed", reason: result.failureReason }, 402);
      }
      providerRef = result.providerRef;
    }

    // 7. Atomically record the transaction + accrue the ledger ------------------
    const recorded = await db.rpc("record_walk_charge", {
      p_walk_id: walkId, p_chat_id: chatId, p_post_id: postId, p_owner_id: ownerId,
      p_sitter_id: sitterId, p_amount_agorot: amountAgorot, p_currency: "ILS",
      p_provider: provider.name, p_provider_ref: providerRef, p_service_day: serviceDay,
    });
    if (recorded.error) {
      // Unique-violation race: another call recorded it first — return that one.
      const again = await db.from("transactions").select("*").eq("walk_id", walkId).maybeSingle();
      if (again.data) return json({ transaction: again.data, idempotent: true }, 200);
      throw new Error(recorded.error.message);
    }
    const tx = recorded.data as Record<string, unknown>;
    const txId = String(tx.id);

    // 8. Write back to Firestore so the app's existing listeners render it ------
    const message = amountAgorot > 0
      ? `תשלום עבור הליכה: ${formatIls(amountAgorot)} ✓`
      : `הליכה נרשמה (כלולה בתעריף היומי) ✓`;

    await createDoc("payments", txId, {
      transactionId: txId,
      walkId, chatId, postId, ownerId, sitterId,
      amountAgorot, currency: "ILS", status: "succeeded",
      provider: provider.name, text: message,
      createdAt: serverTimestamp(),
    });

    await addDoc(`chats/${chatId}/messages`, {
      senderId: ownerId,
      senderName: String(chat.ownerName ?? ""),
      text: message,
      type: "payment",
      walkId,
      amountAgorot,
      paymentStatus: "succeeded",
      createdAt: serverTimestamp(),
    });

    await patchDoc(`chats/${chatId}`, {
      lastMessage: message,
      lastMessageTime: serverTimestamp(),
      lastMessageSenderId: ownerId,
    });

    await db.from("payment_events").insert({
      kind: "charge_succeeded", walk_id: walkId, actor_uid: uid,
      payload: { txId, amountAgorot },
    });

    return json({ transaction: tx }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
