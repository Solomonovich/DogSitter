import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth

struct AuthHelpers {
    static func createFirestoreUserWithRetry(uid: String, data: [String: Any], retryCount: Int = 3) async throws {
        let db = Firestore.firestore()
        for attempt in 1...retryCount {
            do {
                try await db.collection("users").document(uid).setData(data, merge: true)
                return
            } catch {
                if attempt == retryCount {
                    throw error
                }
                try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
            }
        }
    }
}
