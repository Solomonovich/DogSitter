// Mock payment-method management.
//   POST /payment-methods  body: { "last4": "4242", "brand": "visa", "isDefault": true }
//   GET  /payment-methods  -> { methods: [...] }
//
// SANDBOX ONLY. We never receive or store a real PAN — the client sends a brand +
// last4 and we mint a fake token. When the real rail lands, card capture moves to
// the provider SDK and the client sends back a provider token instead.
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

  if (req.method === "GET") {
    const { data, error } = await db
      .from("payment_methods")
      .select("id, brand, last4, is_default, created_at")
      .eq("user_id", uid)
      .order("created_at", { ascending: false });
    if (error) return json({ error: error.message }, 500);
    return json({ methods: data ?? [] }, 200);
  }

  if (req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    const last4 = String(body.last4 ?? "").replace(/\D/g, "").slice(-4);
    if (last4.length !== 4) return json({ error: "valid last4 required" }, 400);
    const brand = String(body.brand ?? "mock").slice(0, 32);
    const isDefault = body.isDefault === true;

    // First card becomes the default automatically.
    const existing = await db.from("payment_methods").select("id").eq("user_id", uid).limit(1);
    const makeDefault = isDefault || (existing.data?.length ?? 0) === 0;

    if (makeDefault) {
      await db.from("payment_methods").update({ is_default: false }).eq("user_id", uid);
    }

    const { data, error } = await db
      .from("payment_methods")
      .insert({
        user_id: uid,
        brand,
        last4,
        provider_token: `mock_pm_${crypto.randomUUID()}`,
        is_default: makeDefault,
      })
      .select("id, brand, last4, is_default, created_at")
      .single();
    if (error) return json({ error: error.message }, 500);
    return json({ method: data }, 201);
  }

  return json({ error: "method not allowed" }, 405);
});
