// ============================================================================
// THE PAYMENT RAIL SEAM.
//
// This file defines the ONE interface every payment rail implements and the
// `getProvider()` switch that selects it at runtime via the PAYMENT_PROVIDER
// secret ("stripe" | "grow" | "mock"). To flip rails you change that secret —
// nothing else in the codebase changes.
//
// Each rail lives in its own file under ./providers/ so this seam stays small:
//   - providers/mock.ts    instant-success sandbox (the `fail_` test hook)
//   - providers/stripe.ts  Stripe (cards, Apple Pay, off-session, refunds, webhooks)
//   - providers/grow.ts    Grow by Meshulam (Israeli: cards + Bit, hosted page, IPN)
//
// Where the abstraction necessarily leaks (card capture is an SDK on Stripe but a
// hosted page on Grow; Apple Pay is native vs in-page; webhook formats differ) it
// is contained behind the discriminated `SetupSession` union and the normalized
// `WebhookEvent` — every rail-specific branch stays inside providers/*.
// ============================================================================

export interface CreateCustomerInput {
  uid: string;
  email?: string;
}

export interface SetupSessionInput {
  uid: string;
  customerId: string;
  /** Deep-link the rail returns to after a hosted capture (Grow). */
  returnUrl: string;
  /** The mobile SDK's Stripe API version — the ephemeral key MUST match it, or
   *  PaymentSheet hangs loading the customer. Sent by the client. */
  apiVersion?: string;
}

/**
 * How the client should capture a card. Discriminated by `kind` so the iOS app
 * branches the capture UI without knowing which rail is active:
 *   - stripe_setup_intent → drive Stripe PaymentSheet with these secrets
 *   - grow_hosted_page    → open this URL in a webview, await the return deep-link
 */
export type SetupSession =
  | {
    kind: "stripe_setup_intent";
    customerId: string;
    setupIntentClientSecret: string;
    ephemeralKeySecret: string;
    publishableKey: string;
  }
  | {
    kind: "grow_hosted_page";
    hostedPageUrl: string;
    processToken: string;
  }
  // Sandbox: the client shows a simple fake-card form and posts last4 to
  // finalize-card. No real SDK / PAN involved.
  | { kind: "mock_manual" };

/** A saved card, normalized across rails. The token is what we charge later. */
export interface SavedCard {
  providerToken: string; // pm_… (Stripe) or Grow card token
  customerId: string;
  brand: string;
  last4: string;
  expMonth?: number;
  expYear?: number;
}

export interface ChargeByTokenRequest {
  amountAgorot: number;
  currency: string; // "ILS"
  customerId: string;
  providerToken: string; // the saved payment method / card token to charge
  ownerId: string;
  sitterId: string;
  /** Idempotency key — the walk id / stay key, so a retry never double-charges. */
  idempotencyKey: string;
  description?: string;
  receiptEmail?: string;
}

export interface ChargeResult {
  // "requires_action" = off-session 3DS/SCA needed; the owner must re-confirm
  // on-session in-app (Israeli cards hit this often).
  status: "succeeded" | "failed" | "requires_action";
  providerRef: string;
  failureReason?: string;
}

export interface RefundResult {
  status: "succeeded" | "failed";
  providerRef: string;
  failureReason?: string;
}

export type WebhookType =
  | "charge_succeeded"
  | "charge_failed"
  | "charge_refunded"
  | "dispute_created"
  | "setup_succeeded"
  | "unknown";

/** A provider webhook, normalized so the settlement routine is rail-agnostic. */
export interface WebhookEvent {
  type: WebhookType;
  eventId: string; // for (provider,event_id) idempotency
  providerRef?: string; // pi_… / charge id / grow tx id
  idempotencyKey?: string; // our walk_id / stay key, from metadata when present
  amountAgorot?: number;
  raw: unknown;
}

export interface PaymentProvider {
  readonly name: "stripe" | "grow" | "mock";

  /** Ensure a provider customer exists for this user; returns its id. */
  createCustomer(input: CreateCustomerInput): Promise<{ customerId: string }>;

  /** Begin card capture; the returned session tells the client how to proceed. */
  createSetupSession(input: SetupSessionInput): Promise<SetupSession>;

  /** Normalize a just-captured card into a SavedCard (brand/last4/token). */
  finalizeSavedCard(
    input: { uid: string; customerId: string; ref: string },
  ): Promise<SavedCard>;

  /** Off-session charge by stored token. MUST be idempotent on idempotencyKey. */
  chargeByToken(req: ChargeByTokenRequest): Promise<ChargeResult>;

  /** Full (amount omitted) or partial refund of a prior charge. */
  refund(
    req: { providerRef: string; amountAgorot?: number; idempotencyKey: string },
  ): Promise<RefundResult>;

  /**
   * Authenticate a webhook by SIGNATURE (never a Firebase token) and normalize
   * it. Returns null on a bad signature so the caller can 400.
   */
  verifyAndParseWebhook(req: Request, rawBody: string): Promise<WebhookEvent | null>;
}

import { MockPaymentProvider } from "./providers/mock.ts";
import { StripeProvider } from "./providers/stripe.ts";
import { GrowProvider } from "./providers/grow.ts";

export function getProvider(): PaymentProvider {
  return providerByName(Deno.env.get("PAYMENT_PROVIDER") ?? "mock");
}

/**
 * Construct a specific rail by name. Used for refunds/webhooks, which must operate
 * on the rail that processed the original charge (recorded in transactions.provider),
 * not necessarily the currently-active PAYMENT_PROVIDER.
 */
export function providerByName(name: string): PaymentProvider {
  switch (name) {
    case "stripe":
      return new StripeProvider();
    case "grow":
      return new GrowProvider();
    case "mock":
    default:
      return new MockPaymentProvider();
  }
}

/** The active rail's name without constructing it (for `payment-config`). */
export function activeProviderName(): "stripe" | "grow" | "mock" {
  const which = Deno.env.get("PAYMENT_PROVIDER") ?? "mock";
  return which === "stripe" || which === "grow" ? which : "mock";
}
