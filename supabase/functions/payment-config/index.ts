// GET /payment-config -> { provider, publishableKey?, applePayMerchantId?, applePaySupported }
//
// Public, low-sensitivity config the iOS app fetches at launch to choose its card-
// capture flow and configure the Stripe SDK. The publishable key is public by
// design; no Firebase token is required so it can be fetched before sign-in.
import { json, preflight } from "../_shared/cors.ts";
import { activeProviderName } from "../_shared/provider.ts";

Deno.serve((req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const provider = activeProviderName();
  return json({
    provider,
    publishableKey: provider === "stripe" ? (Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? "") : "",
    applePayMerchantId: Deno.env.get("STRIPE_APPLE_PAY_MERCHANT_ID") ?? "",
    applePaySupported: provider === "stripe" || provider === "grow",
  }, 200);
});
