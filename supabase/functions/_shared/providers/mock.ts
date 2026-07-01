// Mock rail: instant success, no real money. Keeps the sandbox working end-to-end
// (add a fake card, then charges succeed) and preserves the `fail_` test hook used
// by the idempotency/failure tests.
import type {
  ChargeByTokenRequest,
  ChargeResult,
  CreateCustomerInput,
  PaymentProvider,
  RefundResult,
  SavedCard,
  SetupSession,
  SetupSessionInput,
  WebhookEvent,
} from "../provider.ts";

export class MockPaymentProvider implements PaymentProvider {
  readonly name = "mock" as const;

  // deno-lint-ignore require-await
  async createCustomer(input: CreateCustomerInput): Promise<{ customerId: string }> {
    return { customerId: `mock_cus_${input.uid}` };
  }

  // deno-lint-ignore require-await
  async createSetupSession(_input: SetupSessionInput): Promise<SetupSession> {
    return { kind: "mock_manual" };
  }

  // deno-lint-ignore require-await
  async finalizeSavedCard(
    input: { uid: string; customerId: string; ref: string },
  ): Promise<SavedCard> {
    // `ref` carries the last4 the sandbox form collected.
    const last4 = (input.ref || "4242").replace(/\D/g, "").slice(-4).padStart(4, "0");
    return {
      providerToken: `mock_pm_${crypto.randomUUID()}`,
      customerId: input.customerId,
      brand: "mock",
      last4,
    };
  }

  // deno-lint-ignore require-await
  async chargeByToken(req: ChargeByTokenRequest): Promise<ChargeResult> {
    if (req.idempotencyKey.startsWith("fail_")) {
      return { status: "failed", providerRef: "", failureReason: "mock forced failure" };
    }
    return { status: "succeeded", providerRef: `mock_${req.idempotencyKey}` };
  }

  // deno-lint-ignore require-await
  async refund(
    req: { providerRef: string; amountAgorot?: number; idempotencyKey: string },
  ): Promise<RefundResult> {
    return { status: "succeeded", providerRef: `mock_re_${req.idempotencyKey}` };
  }

  // deno-lint-ignore require-await
  async verifyAndParseWebhook(_req: Request, _rawBody: string): Promise<WebhookEvent | null> {
    // The mock rail emits no webhooks.
    return null;
  }
}
