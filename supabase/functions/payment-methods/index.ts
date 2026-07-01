// Saved-card management for the signed-in user.
//   GET    /payment-methods                 -> { methods: [...] }   (active cards)
//   POST   /payment-methods  { id }         -> set that card as default
//   DELETE /payment-methods  { id }         -> soft-delete that card
//
// Card CAPTURE lives in setup-card / finalize-card (real tokenization); this
// endpoint never receives a PAN.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { serviceClient } from "../_shared/db.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  let uid: string;
  try {
    ({ uid } = await verifyFirebaseToken(req));
  } catch (e) {
    return json({ error: (e as Error).message }, e instanceof AuthError ? 401 : 500);
  }

  const db = serviceClient();

  // ---- list active cards --------------------------------------------------------
  if (req.method === "GET") {
    const { data, error } = await db.from("payment_methods")
      .select("id, brand, last4, exp_month, exp_year, provider, is_default, created_at")
      .eq("user_id", uid)
      .is("deleted_at", null)
      .order("is_default", { ascending: false })
      .order("created_at", { ascending: false });
    if (error) return json({ error: error.message }, 500);
    return json({ methods: data ?? [] }, 200);
  }

  const body = await req.json().catch(() => ({}));
  const id = String(body.id ?? "");
  if (!id) return json({ error: "id required" }, 400);

  // Ownership check — never touch another user's card.
  const owned = await db.from("payment_methods").select("id, is_default")
    .eq("id", id).eq("user_id", uid).is("deleted_at", null).maybeSingle();
  if (!owned.data) return json({ error: "card not found" }, 404);

  // ---- set default --------------------------------------------------------------
  if (req.method === "POST") {
    await db.from("payment_methods").update({ is_default: false }).eq("user_id", uid);
    const { error } = await db.from("payment_methods").update({ is_default: true }).eq("id", id);
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true }, 200);
  }

  // ---- soft-delete (and promote a new default if needed) ------------------------
  if (req.method === "DELETE") {
    const { error } = await db.from("payment_methods")
      .update({ deleted_at: new Date().toISOString(), is_default: false }).eq("id", id);
    if (error) return json({ error: error.message }, 500);

    if (owned.data.is_default) {
      const next = await db.from("payment_methods").select("id")
        .eq("user_id", uid).is("deleted_at", null)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (next.data) {
        await db.from("payment_methods").update({ is_default: true }).eq("id", next.data.id);
      }
    }
    return json({ ok: true }, 200);
  }

  return json({ error: "method not allowed" }, 405);
});
