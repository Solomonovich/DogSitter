// GET /get-balance -> { ownerChargedAgorot, sitterAccruedAgorot, currency }
//
// Returns the caller's running ledger totals (collect-only: sitterAccrued is earned
// but not yet paid out). The transaction *history* is read from Firestore (the
// payments collection) by the app; this endpoint is just the authoritative totals.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { serviceClient } from "../_shared/db.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  let uid: string;
  try {
    ({ uid } = await verifyFirebaseToken(req));
  } catch (e) {
    return json({ error: (e as Error).message }, e instanceof AuthError ? 401 : 500);
  }

  const db = serviceClient();
  const { data, error } = await db
    .from("balances")
    .select("owner_charged_agorot, sitter_accrued_agorot, currency")
    .eq("user_id", uid)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);

  return json({
    ownerChargedAgorot: Number(data?.owner_charged_agorot ?? 0),
    sitterAccruedAgorot: Number(data?.sitter_accrued_agorot ?? 0),
    currency: data?.currency ?? "ILS",
  }, 200);
});
