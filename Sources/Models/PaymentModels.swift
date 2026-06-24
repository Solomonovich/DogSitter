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
    var walkId: String
    var chatId: String
    var postId: String
    var ownerId: String
    var sitterId: String
    var amountAgorot: Int
    var currency: String
    var status: String          // PaymentStatus raw value
    var provider: String
    var text: String?
    @ServerTimestamp var createdAt: Timestamp?

    var paymentStatus: PaymentStatus { PaymentStatus(rawValue: status) ?? .pending }
    var formattedAmount: String { Money.formatILS(amountAgorot) }
}

/// A saved (mock) card, decoded from the `payment-methods` function JSON.
struct PaymentMethod: Identifiable, Decodable {
    let id: String
    let brand: String
    let last4: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, brand, last4
        case isDefault = "is_default"
    }

    var maskedNumber: String { "•••• \(last4)" }
}

/// The caller's running ledger totals, decoded from `get-balance`.
struct Balance: Decodable {
    let ownerChargedAgorot: Int
    let sitterAccruedAgorot: Int
    let currency: String

    static let zero = Balance(ownerChargedAgorot: 0, sitterAccruedAgorot: 0, currency: "ILS")
}

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
