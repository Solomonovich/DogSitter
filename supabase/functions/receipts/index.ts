// GET /receipts                      -> { receipts: [...] }   (the caller's receipts)
// GET /receipts?transactionId=<uuid>  -> { receipt: {...} }
//
// Israeli receipts with a VAT breakdown (net / VAT / gross). A participant may read
// their own; written only by the backend on a successful charge.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { serviceClient } from "../_shared/db.ts";

function shape(r: Record<string, unknown>) {
  return {
    id: r.id,
    number: r.number,
    transactionId: r.transaction_id,
    netAgorot: Number(r.net_agorot),
    vatAgorot: Number(r.vat_agorot),
    grossAgorot: Number(r.gross_agorot),
    vatRateBps: Number(r.vat_rate_bps),
    ownerId: r.owner_id,
    sitterId: r.sitter_id,
    issuedAt: r.issued_at,
  };
}

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
  const transactionId = new URL(req.url).searchParams.get("transactionId");

  if (transactionId) {
    const { data, error } = await db.from("receipts").select("*").eq("transaction_id", transactionId).maybeSingle();
    if (error) return json({ error: error.message }, 500);
    if (!data) return json({ error: "receipt not found" }, 404);
    if (data.owner_id !== uid && data.sitter_id !== uid) return json({ error: "forbidden" }, 403);
    return json({ receipt: shape(data) }, 200);
  }

  // List: the caller's receipts (as owner or sitter).
  const { data, error } = await db.from("receipts")
    .select("*")
    .or(`owner_id.eq.${uid},sitter_id.eq.${uid}`)
    .order("issued_at", { ascending: false });
  if (error) return json({ error: error.message }, 500);
  return json({ receipts: (data ?? []).map(shape) }, 200);
});
