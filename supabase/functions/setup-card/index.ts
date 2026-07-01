// POST /setup-card -> SetupSession
//
// Begins card capture for the signed-in user: ensures a provider customer exists
// (mapped in payment_customers), then returns the discriminated SetupSession the
// client uses to drive the rail-appropriate capture UI (Stripe PaymentSheet, Grow
// hosted page, or the sandbox form).
import { json, preflight } from "../_shared/cors.ts";
import { AuthError, verifyFirebaseToken } from "../_shared/firebaseAuth.ts";
import { getProvider } from "../_shared/provider.ts";
import { getCustomerId } from "../_shared/cards.ts";
import { serviceClient } from "../_shared/db.ts";

const RETURN_URL = "dogsitter://pay";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  let uid: string;
  let email: string | undefined;
  try {
    ({ uid, email } = await verifyFirebaseToken(req));
  } catch (e) {
    return json({ error: (e as Error).message }, e instanceof AuthError ? 401 : 500);
  }

  const body = await req.json().catch(() => ({}));
  const apiVersion = typeof body.stripeApiVersion === "string" ? body.stripeApiVersion : undefined;

  const db = serviceClient();
  const provider = getProvider();

  try {
    let customerId = await getCustomerId(db, uid, provider.name);
    if (!customerId) {
      const created = await provider.createCustomer({ uid, email });
      customerId = created.customerId;
      await db.from("payment_customers")
        .upsert({ user_id: uid, provider: provider.name, customer_id: customerId },
          { onConflict: "user_id,provider" });
    }

    const session = await provider.createSetupSession({ uid, customerId, returnUrl: RETURN_URL, apiVersion });
    return json({ session }, 200);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
