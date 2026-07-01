// POST /record-payout   body: { "sitterId", "amountAgorot", "method", "reference"?, "note"? }
//
// ADMIN ONLY. Records a manual sitter payout (disbursed offline via PayBox Young /
// Bit) and decrements the sitter's available balance. Mirrors the payout to
// Firestore (payouts/{id}) so the sitter's app shows it. Most sitters are minors,
// so payouts are intentionally manual — there is no automated KYC transfer.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, isAdmin, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { createDoc, serverTimestamp } from "../_shared/firestore.ts";
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
  if (!isAdmin(uid)) return json({ error: "forbidden" }, 403);

  const body = await req.json().catch(() => ({}));
  const sitterId = String(body.sitterId ?? "");
  const amount = Number(body.amountAgorot ?? 0);
  const method = ["paybox", "bit", "manual"].includes(String(body.method)) ? String(body.method) : "manual";
  if (!sitterId || !(amount > 0)) return json({ error: "sitterId and positive amountAgorot required" }, 400);

  const db = serviceClient();

  try {
    const recorded = await db.rpc("record_payout", {
      p_sitter_id: sitterId,
      p_amount_agorot: amount,
      p_method: method,
      p_reference: body.reference ? String(body.reference) : null,
      p_note: body.note ? String(body.note) : null,
      p_created_by: uid,
    });
    if (recorded.error) return json({ error: recorded.error.message }, 422);
    const payout = recorded.data as Record<string, unknown>;
    const payoutId = String(payout.id);

    await createDoc("payouts", payoutId, {
      payoutId,
      sitterId,
      amountAgorot: amount,
      currency: "ILS",
      status: "paid",
      method,
      reference: body.reference ?? null,
      note: body.note ?? null,
      createdAt: serverTimestamp(),
    });

    return json({ payout }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
