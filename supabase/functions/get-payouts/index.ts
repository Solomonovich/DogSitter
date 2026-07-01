// GET /get-payouts -> { payouts: [...], accruedAgorot, paidOutAgorot, availableAgorot }
//
// The signed-in sitter's payout history plus their accrued / paid-out / available
// totals (available = accrued − paid out).
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { serviceClient } from "../_shared/db.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "GET" && req.method !== "POST") return json({ error: "method not allowed" }, 405);

  let uid: string;
  try {
    ({ uid } = await verifyFirebaseToken(req));
  } catch (e) {
    return json({ error: (e as Error).message }, e instanceof AuthError ? 401 : 500);
  }

  const db = serviceClient();

  const [payoutsRes, balanceRes] = await Promise.all([
    db.from("payouts")
      .select("id, amount_agorot, status, method, reference, note, created_at, paid_at")
      .eq("sitter_id", uid)
      .order("created_at", { ascending: false }),
    db.from("balances")
      .select("sitter_accrued_agorot, sitter_paid_out_agorot")
      .eq("user_id", uid)
      .maybeSingle(),
  ]);
  if (payoutsRes.error) return json({ error: payoutsRes.error.message }, 500);

  const accrued = Number(balanceRes.data?.sitter_accrued_agorot ?? 0);
  const paidOut = Number(balanceRes.data?.sitter_paid_out_agorot ?? 0);

  const payouts = (payoutsRes.data ?? []).map((p) => ({
    id: p.id,
    amountAgorot: Number(p.amount_agorot),
    status: p.status,
    method: p.method,
    reference: p.reference,
    note: p.note,
    createdAt: p.created_at,
    paidAt: p.paid_at,
  }));

  return json({
    payouts,
    accruedAgorot: accrued,
    paidOutAgorot: paidOut,
    availableAgorot: Math.max(0, accrued - paidOut),
  }, 200);
});
