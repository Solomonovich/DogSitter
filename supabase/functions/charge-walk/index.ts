// POST /charge-walk   body: { "walkId": "<id>" }
//
// Charges the owner for one completed walk (Walking posts) and accrues the sitter's
// NET earnings. Card-on-file required; idempotent on walkId; off-session via the
// active rail (see _shared/charge.ts). Called from AppState.stopWalk() with the
// user's Firebase ID token.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { getDoc } from "../_shared/firestore.ts";
import { computeWalkChargeAgorot, formatIls, mappedPostType, serviceDayString } from "../_shared/billing.ts";
import { runCharge } from "../_shared/charge.ts";
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

  const { walkId } = await req.json().catch(() => ({}));
  if (!walkId || typeof walkId !== "string") return json({ error: "walkId required" }, 400);

  const db = serviceClient();

  try {
    // Source-of-truth reads + re-verification against Firestore.
    const walk = await getDoc(`walks/${walkId}`);
    if (!walk) return json({ error: "walk not found" }, 404);
    if (walk.status !== "completed") return json({ error: "walk not completed" }, 409);

    const ownerId = String(walk.ownerId ?? "");
    const sitterId = String(walk.sitterId ?? "");
    const chatId = String(walk.chatId ?? "");
    const postId = String(walk.postId ?? "");

    if (uid !== ownerId && uid !== sitterId) return json({ error: "forbidden" }, 403);

    const chat = await getDoc(`chats/${chatId}`);
    if (!chat) return json({ error: "chat not found" }, 404);
    if (chat.approved !== true) return json({ error: "booking not approved" }, 409);
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

    const amountAgorot = computeWalkChargeAgorot(payAmount);

    return await runCharge({
      db,
      uid,
      walkKey: walkId,
      chatId,
      postId,
      ownerId,
      sitterId,
      ownerName: String(chat.ownerName ?? ""),
      amountAgorot,
      serviceDay: serviceDayString(walk.endTime as string | undefined),
      description: `DogSitter walk ${walkId}`,
      successText: `תשלום עבור הליכה: ${formatIls(amountAgorot)} ✓`,
      paymentDocExtra: { walkId },
      chatMessageExtra: { walkId },
    });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
