import Foundation

/// F-16: build an unguessable Cloudinary public_id. The old scheme was fully
/// derived from user/pet ids (`"<petId>_<index>"`), letting anyone who learns
/// those ids enumerate or overwrite another user's images. Appending a random
/// token removes that predictability. The canonical URL is stored in Firestore,
/// so reads never need to reconstruct the id.
public enum CloudinaryPublicID {
    public static func make(prefix: String) -> String {
        let token = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(16)
        return "\(prefix)_\(token)"
    }
}
