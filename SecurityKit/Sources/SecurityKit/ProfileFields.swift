import Foundation

/// F-01: build the minimal, allow-listed payload for a profile update so the
/// client can never send privileged fields (role, email, averageRating,
/// totalReviews). Mirrors the editable fields permitted by the Firestore rules.
public enum ProfileFields {
    /// The only fields a user may change on their own profile document.
    public static let editableKeys: Set<String> = [
        "name", "fullName", "username", "address", "phone", "photoURL", "age"
    ]

    /// Returns only allow-listed keys. `phone` is included for sitters only,
    /// matching the existing edit form behaviour.
    public static func updatePayload(
        name: String,
        username: String,
        address: String,
        phone: String?,
        isSitter: Bool
    ) -> [String: String] {
        var payload: [String: String] = [
            "name": name,
            "username": username,
            "address": address
        ]
        if isSitter, let phone, !phone.isEmpty {
            payload["phone"] = phone
        }
        return payload
    }
}
