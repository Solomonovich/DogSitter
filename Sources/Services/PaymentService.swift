import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Public connection details for the Supabase payments backend. Both values are
/// PUBLIC (the anon key is safe to ship). Until the backend project exists they stay
/// empty and `PaymentService` degrades gracefully — the app runs, charges just no-op.
///
/// Fill these in after creating the Supabase project (see `supabase/README.md`).
enum PaymentConfig {
    /// Supabase project `dogsitter-payments` (ref zqwzfjpymktfeoripicl, eu-central-1).
    static let functionsBaseURL = "https://zqwzfjpymktfeoripicl.supabase.co/functions/v1"
    /// Public anon key — safe to ship; sent as the `apikey` header.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inpxd3pmanB5bWt0ZmVvcmlwaWNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzMDkzNDksImV4cCI6MjA5Nzg4NTM0OX0.3hgaNdAB-9mXQbfmPcTJQBqLEswsrYtOLTCvpqJYSJE"

    static var isConfigured: Bool { !functionsBaseURL.isEmpty && !anonKey.isEmpty }
}

enum PaymentError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:    return "התשלומים אינם מוגדרים עדיין"
        case .notAuthenticated: return "יש להתחבר כדי לבצע תשלום"
        case .server(let m):    return m
        }
    }
}

/// Talks to the Supabase payment Edge Functions over plain HTTPS (no Supabase SDK),
/// authenticating every call with the user's Firebase ID token. Payment *history* is
/// read straight from Firestore (`payments`) so the app keeps a single read path.
///
/// Singleton (like `NotificationManager`/`WalkLiveActivityManager`) so `AppState`
/// can trigger a charge, while SwiftUI views observe it as an `@EnvironmentObject`.
@MainActor
final class PaymentService: ObservableObject {
    static let shared = PaymentService()
    private init() {}

    @Published private(set) var transactions: [PaymentTransaction] = []
    @Published private(set) var balance: Balance = .zero
    @Published private(set) var paymentMethods: [PaymentMethod] = []
    @Published var isProcessing = false
    @Published var lastError: String?

    private let db = Firestore.firestore()
    private var paymentsListener: ListenerRegistration?

    // MARK: - History (Firestore listener)

    /// Live payment history for the signed-in user, scoped to their role so the
    /// participant-only read rule can authorize the query.
    func startListening(uid: String, role: UserRole) {
        stopListening()
        let field = role == .owner ? "ownerId" : "sitterId"
        paymentsListener = db.collection("payments")
            .whereField(field, isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.dbg("payments listen: \(error)"); return }
                self.transactions = snapshot?.documents.compactMap {
                    try? $0.data(as: PaymentTransaction.self)
                } ?? []
            }
    }

    func stopListening() {
        paymentsListener?.remove()
        paymentsListener = nil
    }

    // MARK: - Charge (per completed walk)

    /// Charges the owner for a completed walk (Walking posts). Idempotent server-side,
    /// so a retry or a double "stop walk" is safe. The server no-ops this for Overnight
    /// posts (their walks are free). No-ops entirely when payments aren't configured.
    func chargeForWalk(walkId: String) async {
        guard PaymentConfig.isConfigured else { dbg("not configured; skip charge \(walkId)"); return }
        do {
            _ = try await call(path: "charge-walk", method: "POST", body: ["walkId": walkId])
        } catch {
            dbg("chargeForWalk(\(walkId)) failed: \(error)")
        }
    }

    /// Ends an Overnight stay and charges the owner `nights × rate` once (idempotent
    /// per chat). Returns true on success so the UI can react. No-ops when unconfigured.
    @discardableResult
    func endStay(chatId: String) async -> Bool {
        guard PaymentConfig.isConfigured else { lastError = PaymentError.notConfigured.errorDescription; return false }
        isProcessing = true
        defer { isProcessing = false }
        do {
            _ = try await call(path: "charge-stay", method: "POST", body: ["chatId": chatId])
            return true
        } catch {
            lastError = (error as? PaymentError)?.errorDescription ?? error.localizedDescription
            dbg("endStay(\(chatId)) failed: \(error)")
            return false
        }
    }

    // MARK: - Wallet reads

    func loadBalance() async {
        guard PaymentConfig.isConfigured else { return }
        do {
            let data = try await call(path: "get-balance", method: "GET", body: nil)
            balance = try JSONDecoder().decode(Balance.self, from: data)
        } catch { dbg("loadBalance: \(error)") }
    }

    func loadPaymentMethods() async {
        guard PaymentConfig.isConfigured else { return }
        do {
            let data = try await call(path: "payment-methods", method: "GET", body: nil)
            paymentMethods = try JSONDecoder().decode(MethodsResponse.self, from: data).methods
        } catch { dbg("loadPaymentMethods: \(error)") }
    }

    /// Adds a mock card. Returns true on success. SANDBOX ONLY — never send a real PAN.
    @discardableResult
    func addPaymentMethod(last4: String, brand: String, makeDefault: Bool) async -> Bool {
        guard PaymentConfig.isConfigured else { lastError = PaymentError.notConfigured.errorDescription; return false }
        isProcessing = true
        defer { isProcessing = false }
        do {
            _ = try await call(path: "payment-methods", method: "POST",
                               body: ["last4": last4, "brand": brand, "isDefault": makeDefault])
            await loadPaymentMethods()
            return true
        } catch {
            lastError = (error as? PaymentError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private struct MethodsResponse: Decodable { let methods: [PaymentMethod] }

    // MARK: - HTTP

    private func call(path: String, method: String, body: [String: Any]?) async throws -> Data {
        guard PaymentConfig.isConfigured, let url = URL(string: "\(PaymentConfig.functionsBaseURL)/\(path)") else {
            throw PaymentError.notConfigured
        }
        guard let token = try await Auth.auth().currentUser?.getIDToken() else {
            throw PaymentError.notAuthenticated
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(PaymentConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(token, forHTTPHeaderField: "x-firebase-token")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw PaymentError.server(message ?? "שגיאת שרת (\((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        return data
    }

    private func dbg(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[PaymentService] \(message())")
        #endif
    }
}
