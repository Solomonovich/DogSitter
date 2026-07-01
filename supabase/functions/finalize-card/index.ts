// POST /finalize-card   body: { "ref": "<pm_/seti_/last4>", "makeDefault": true }
//
// Called after a successful capture: normalizes the saved card via the rail and
// persists it in payment_methods (token + customer + brand/last4/exp). The first
// card, or one flagged makeDefault, becomes the default charged card.
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { getProvider } from "../_shared/provider.ts";
import { getCustomerId } from "../_shared/cards.ts";
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

  const body = await req.json().catch(() => ({}));
  const ref = String(body.ref ?? "");
  const wantDefault = body.makeDefault === true;

  const db = serviceClient();
  const provider = getProvider();

  try {
    const customerId = await getCustomerId(db, uid, provider.name);
    if (!customerId) return json({ error: "no customer — call setup-card first" }, 409);

    const card = await provider.finalizeSavedCard({ uid, customerId, ref });

    // First active card becomes default automatically.
    const existing = await db.from("payment_methods").select("id")
      .eq("user_id", uid).eq("provider", provider.name).is("deleted_at", null).limit(1);
    const makeDefault = wantDefault || (existing.data?.length ?? 0) === 0;
    if (makeDefault) {
      await db.from("payment_methods").update({ is_default: false })
        .eq("user_id", uid).eq("provider", provider.name);
    }

    const { data, error } = await db.from("payment_methods").insert({
      user_id: uid,
      provider: provider.name,
      brand: card.brand,
      last4: card.last4,
      exp_month: card.expMonth ?? null,
      exp_year: card.expYear ?? null,
      provider_token: card.providerToken,
      customer_id: card.customerId,
      is_default: makeDefault,
    }).select("id, brand, last4, exp_month, exp_year, is_default, created_at").single();
    if (error) return json({ error: error.message }, 500);

    return json({ method: data }, 201);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
