// POST /charge-stay   body: { "chatId": "<id>" }
//
// Charges an OVERNIGHT stay once, at end of stay: nights × per-night rate. Card-on-
// file required; idempotent on the synthetic walk id `stay_<chatId>`; off-session
// via the active rail (see _shared/charge.ts). Called when the sitter taps "End stay".
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { getDoc, serverTimestamp } from "../_shared/firestore.ts";
import { computeNights, computeStayChargeAgorot, formatIls, mappedPostType, serviceDayString } from "../_shared/billing.ts";
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

    const nights = computeNights(post.startDate as string | undefined, post.endDate as string | undefined);
    const amountAgorot = computeStayChargeAgorot(perNight, nights);
    const nightWord = nights === 1 ? "לילה" : "לילות";

    return await runCharge({
      db,
      uid,
      walkKey: `stay_${chatId}`,
      chatId,
      postId,
      ownerId,
      sitterId,
      ownerName: String(chat.ownerName ?? ""),
      amountAgorot,
      serviceDay: serviceDayString(post.endDate as string | undefined),
      description: `DogSitter stay ${chatId} (${nights} ${nightWord})`,
      successText: `תשלום עבור ${nights} ${nightWord}: ${formatIls(amountAgorot)} ✓`,
      paymentDocExtra: { walkId: `stay_${chatId}` },
      chatPatchExtra: { stayCompletedAt: serverTimestamp() },
    });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
