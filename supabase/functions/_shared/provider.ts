// ============================================================================
// THE PAYMENT RAIL SEAM.
//
// This file is the ONLY thing that knows how to actually move money. Today it is a
// MOCK that always succeeds. To go live, implement `PaymentProvider` with a real
// processor (Stripe Connect, or an Israeli processor — Meshulam/Grow, Tranzila,
// PayPlus; Bit for P2P) and swap which instance `getProvider()` returns. Nothing
// else in the codebase needs to change.
//
// See the `payments-real-rail-deferred` memory for the full go-live checklist.
// ============================================================================

export interface ChargeRequest {
  amountAgorot: number;
  currency: string;
  ownerId: string;
  sitterId: string;
  walkId: string;
  /** Idempotency key — the walk id, so a retry never double-charges. */
  idempotencyKey: string;
}

export interface ChargeResult {
  status: "succeeded" | "failed";
  providerRef: string;
  failureReason?: string;
}

export interface PaymentProvider {
  readonly name: string;
  charge(req: ChargeRequest): Promise<ChargeResult>;
}

/** Mock rail: succeeds instantly, no real money. */
class MockPaymentProvider implements PaymentProvider {
  readonly name = "mock";

  // deno-lint-ignore require-await
  async charge(req: ChargeRequest): Promise<ChargeResult> {
    // A test hook to exercise the failure path: a walk id prefixed "fail_" fails.
    if (req.walkId.startsWith("fail_")) {
      return { status: "failed", providerRef: "", failureReason: "mock forced failure" };
    }
    return { status: "succeeded", providerRef: `mock_${req.idempotencyKey}` };
  }
}

export function getProvider(): PaymentProvider {
  const which = Deno.env.get("PAYMENT_PROVIDER") ?? "mock";
  switch (which) {
    // case "stripe":   return new StripeProvider();    // ← real rail goes here
    // case "meshulam": return new MeshulamProvider();
    case "mock":
    default:
      return new MockPaymentProvider();
  }
}
