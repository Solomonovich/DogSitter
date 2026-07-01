import Foundation
import FirebaseFirestore

// Payment models. Money is integer **agorot** (1 ILS = 100 agorot) everywhere, to
// match the Supabase ledger and avoid floating-point drift. `PaymentTransaction`
// mirrors the `payments/{id}` doc the `charge-walk` Edge Function writes back to
// Firestore; `PaymentMethod` / `Balance` are decoded from the function JSON.

enum PaymentStatus: String, Codable {
    case pending
    case succeeded
    case failed
    case refunded

    var displayName: String {
        switch self {
        case .pending:   return "ממתין"
        case .succeeded: return "שולם"
        case .failed:    return "נכשל"
        case .refunded:  return "הוחזר"
        }
    }
}

/// A single processed walk charge, as written back to Firestore `payments/{id}`.
struct PaymentTransaction: Identifiable, Codable {
    @DocumentID var id: String?
    var transactionId: String?
    var walkId: String?
    var chatId: String
    var postId: String
    var ownerId: String
    var sitterId: String
    var amountAgorot: Int
    var currency: String
    var status: String          // PaymentStatus raw value
    var provider: String
    var text: String?
    /// Set on a failed charge: the owner must re-confirm an off-session 3DS charge.
    var requiresAction: Bool?
    var failureReason: String?
    @ServerTimestamp var createdAt: Timestamp?

    var paymentStatus: PaymentStatus { PaymentStatus(rawValue: status) ?? .pending }
    var formattedAmount: String { Money.formatILS(amountAgorot) }
    var needsAttention: Bool { paymentStatus == .failed }
}

/// A saved card, decoded from the `payment-methods` function JSON.
struct PaymentMethod: Identifiable, Decodable {
    let id: String
    let brand: String
    let last4: String
    let isDefault: Bool
    let expMonth: Int?
    let expYear: Int?
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case id, brand, last4, provider
        case isDefault = "is_default"
        case expMonth = "exp_month"
        case expYear = "exp_year"
    }

    var maskedNumber: String { "•••• \(last4)" }
    var expiryLabel: String? {
        guard let m = expMonth, let y = expYear else { return nil }
        return String(format: "%02d/%02d", m, y % 100)
    }
}

/// The caller's running ledger totals, decoded from `get-balance`. New fields are
/// decoded defensively so an older backend response still parses.
struct Balance: Decodable {
    let ownerChargedAgorot: Int
    let ownerRefundedAgorot: Int
    let sitterAccruedAgorot: Int
    let sitterPaidOutAgorot: Int
    let sitterAvailableAgorot: Int
    let currency: String

    enum CodingKeys: String, CodingKey {
        case ownerChargedAgorot, ownerRefundedAgorot, sitterAccruedAgorot
        case sitterPaidOutAgorot, sitterAvailableAgorot, currency
    }

    init(ownerChargedAgorot: Int, ownerRefundedAgorot: Int, sitterAccruedAgorot: Int,
         sitterPaidOutAgorot: Int, sitterAvailableAgorot: Int, currency: String) {
        self.ownerChargedAgorot = ownerChargedAgorot
        self.ownerRefundedAgorot = ownerRefundedAgorot
        self.sitterAccruedAgorot = sitterAccruedAgorot
        self.sitterPaidOutAgorot = sitterPaidOutAgorot
        self.sitterAvailableAgorot = sitterAvailableAgorot
        self.currency = currency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ownerChargedAgorot = try c.decodeIfPresent(Int.self, forKey: .ownerChargedAgorot) ?? 0
        ownerRefundedAgorot = try c.decodeIfPresent(Int.self, forKey: .ownerRefundedAgorot) ?? 0
        sitterAccruedAgorot = try c.decodeIfPresent(Int.self, forKey: .sitterAccruedAgorot) ?? 0
        sitterPaidOutAgorot = try c.decodeIfPresent(Int.self, forKey: .sitterPaidOutAgorot) ?? 0
        sitterAvailableAgorot = try c.decodeIfPresent(Int.self, forKey: .sitterAvailableAgorot)
            ?? max(0, sitterAccruedAgorot - sitterPaidOutAgorot)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "ILS"
    }

    static let zero = Balance(ownerChargedAgorot: 0, ownerRefundedAgorot: 0, sitterAccruedAgorot: 0,
                              sitterPaidOutAgorot: 0, sitterAvailableAgorot: 0, currency: "ILS")
}

/// Public payment config from `payment-config`, fetched at launch to pick the
/// capture flow and configure the Stripe SDK.
struct PaymentConfigResponse: Decodable {
    let provider: String          // "stripe" | "grow" | "mock"
    let publishableKey: String
    let applePayMerchantId: String
    let applePaySupported: Bool
}

/// How the client should capture a card, mirrored from the backend's discriminated
/// `SetupSession`. Flat optionals keyed by `kind` so one struct covers every rail.
struct SetupSession: Decodable {
    let kind: String              // "stripe_setup_intent" | "grow_hosted_page" | "mock_manual"
    // Stripe
    let customerId: String?
    let setupIntentClientSecret: String?
    let ephemeralKeySecret: String?
    let publishableKey: String?
    // Grow
    let hostedPageUrl: String?
    let processToken: String?
}

struct SetupSessionResponse: Decodable { let session: SetupSession }

/// A manual sitter payout, decoded from `get-payouts`.
struct Payout: Identifiable, Decodable {
    let id: String
    let amountAgorot: Int
    let status: String
    let method: String        // "paybox" | "bit" | "manual"
    let reference: String?
    let note: String?
    let createdAt: String?

    var formattedAmount: String { Money.formatILS(amountAgorot) }
    var methodLabel: String {
        switch method {
        case "paybox": return "PayBox"
        case "bit":    return "ביט"
        default:        return "העברה ידנית"
        }
    }
}

struct PayoutsResponse: Decodable {
    let payouts: [Payout]
    let accruedAgorot: Int
    let paidOutAgorot: Int
    let availableAgorot: Int
}

/// An Israeli receipt with a VAT breakdown, decoded from `receipts`.
struct Receipt: Identifiable, Decodable {
    let id: String
    let number: String
    let transactionId: String
    let netAgorot: Int
    let vatAgorot: Int
    let grossAgorot: Int
    let vatRateBps: Int
    let issuedAt: String?

    var vatRatePercent: Int { vatRateBps / 100 }
    var formattedNet: String { Money.formatILS(netAgorot) }
    var formattedVat: String { Money.formatILS(vatAgorot) }
    var formattedGross: String { Money.formatILS(grossAgorot) }
}

struct ReceiptResponse: Decodable { let receipt: Receipt }

enum Money {
    /// Formats agorot as an ILS currency string (e.g. 15050 -> "₪150.50").
    static func formatILS(_ agorot: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "ILS"
        formatter.locale = Locale(identifier: "he_IL")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = agorot % 100 == 0 ? 0 : 2
        let value = Double(agorot) / 100.0
        return formatter.string(from: NSNumber(value: value)) ?? "₪\(value)"
    }
}
