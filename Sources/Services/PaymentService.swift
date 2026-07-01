import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Public connection details for the Supabase payments backend. Both values are
/// PUBLIC (the anon key is safe to ship). Until the backend project exists they stay
/// empty and `PaymentService` degrades gracefully — the app runs, charges just no-op.
///
/// Fill these in after creating the Supabase project (see `supabase/README.md`).
enum PaymentConfig {
    /// Supabase project `dogsitter-payments` (ref szxldlkbxkepydjincgk, eu-central-1).
    static let functionsBaseURL = "https://szxldlkbxkepydjincgk.supabase.co/functions/v1"
    /// Public anon key — safe to ship; sent as the `apikey` header.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN6eGxkbGtieGtlcHlkamluY2drIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4NTI2MTIsImV4cCI6MjA5ODQyODYxMn0.NAh6sTZtd6I4bBUdj7sm9v4Z8TWdIKreo9pA3Hw4ddo"

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
    @Published private(set) var config: PaymentConfigResponse?
    @Published private(set) var payouts: [Payout] = []
    @Published private(set) var payoutAvailableAgorot: Int = 0
    @Published var isProcessing = false
    @Published var lastError: String?

    /// The active rail, once `loadConfig()` has run ("stripe" | "grow" | "mock").
    var activeProvider: String { config?.provider ?? "mock" }
    /// Only a real rail requires a saved card before a booking can be approved.
    var requiresCardForBooking: Bool { activeProvider == "stripe" || activeProvider == "grow" }

    private let db = Firestore.firestore()
    private var paymentsListener: ListenerRegistration?

    // MARK: - History (Firestore listener)

    /// Live payment history for the signed-in user, scoped to their role so the
    /// participant-only read rule can authorize the query.
    private var alertedFailures: Set<String> = []
    private var failuresSeeded = false

    func startListening(uid: String, role: UserRole) {
        stopListening()
        failuresSeeded = false
        let field = role == .owner ? "ownerId" : "sitterId"
        paymentsListener = db.collection("payments")
            .whereField(field, isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.dbg("payments listen: \(error)"); return }
                let txs = snapshot?.documents.compactMap {
                    try? $0.data(as: PaymentTransaction.self)
                } ?? []
                self.transactions = txs
                if role == .owner { self.notifyNewFailures(txs) }
            }
    }

    /// Local alert when a charge fails (no backend push yet — see Phase 4 notes).
    /// The first snapshot seeds known failures silently so launch never spams.
    private func notifyNewFailures(_ txs: [PaymentTransaction]) {
        let failed = txs.filter { $0.paymentStatus == .failed }
        let ids = failed.compactMap { $0.id ?? $0.transactionId }
        if !failuresSeeded {
            alertedFailures.formUnion(ids)
            failuresSeeded = true
            return
        }
        for tx in failed {
            let id = tx.id ?? tx.transactionId ?? ""
            guard !id.isEmpty, !alertedFailures.contains(id) else { continue }
            alertedFailures.insert(id)
            let body = tx.requiresAction == true
                ? "נדרש אימות לתשלום. יש לאשר מחדש את התשלום."
                : "תשלום נכשל. נא לעדכן את אמצעי התשלום."
            NotificationManager.shared.scheduleLocalAlert(title: "בעיה בתשלום", body: body, identifier: "pay_fail_\(id)")
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

    /// Public rail config (provider + Stripe publishable key). Safe to call pre-auth.
    func loadConfig() async {
        guard PaymentConfig.isConfigured else { return }
        do {
            let data = try await call(path: "payment-config", method: "GET", body: nil, requireAuth: false)
            config = try JSONDecoder().decode(PaymentConfigResponse.self, from: data)
        } catch { dbg("loadConfig: \(error)") }
    }

    // MARK: - Card capture (real tokenization)

    /// Begins card capture; the returned session tells the UI how to proceed
    /// (Stripe PaymentSheet, Grow hosted page, or the sandbox form).
    func beginCardSetup(apiVersion: String? = nil) async throws -> SetupSession {
        var body: [String: Any] = [:]
        if let apiVersion { body["stripeApiVersion"] = apiVersion }
        let data = try await call(path: "setup-card", method: "POST", body: body)
        return try JSONDecoder().decode(SetupSessionResponse.self, from: data).session
    }

    /// Persists a just-captured card. `ref` is the rail's token/intent id (or last4
    /// for the sandbox form). Refreshes the saved-card list on success.
    @discardableResult
    func finalizeCard(ref: String, makeDefault: Bool) async -> Bool {
        guard PaymentConfig.isConfigured else { lastError = PaymentError.notConfigured.errorDescription; return false }
        isProcessing = true
        defer { isProcessing = false }
        do {
            _ = try await call(path: "finalize-card", method: "POST",
                               body: ["ref": ref, "makeDefault": makeDefault])
            await loadPaymentMethods()
            return true
        } catch {
            lastError = (error as? PaymentError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deletePaymentMethod(id: String) async -> Bool {
        do {
            _ = try await call(path: "payment-methods", method: "DELETE", body: ["id": id])
            await loadPaymentMethods()
            return true
        } catch {
            lastError = (error as? PaymentError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setDefaultPaymentMethod(id: String) async -> Bool {
        do {
            _ = try await call(path: "payment-methods", method: "POST", body: ["id": id])
            await loadPaymentMethods()
            return true
        } catch {
            lastError = (error as? PaymentError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    // MARK: - Booking gate

    /// For the approve-booking gate: true when booking must be blocked because the
    /// owner has no card on file. Only enforced once a real rail is active, so the
    /// app keeps working on the mock rail.
    func bookingBlockedByMissingCard() async -> Bool {
        guard requiresCardForBooking else { return false }
        await loadPaymentMethods()
        return paymentMethods.isEmpty
    }

    // MARK: - Payouts / refunds / receipts

    /// Sitter payout history + available-to-pay-out total.
    func loadPayouts() async {
        guard PaymentConfig.isConfigured else { return }
        do {
            let data = try await call(path: "get-payouts", method: "GET", body: nil)
            let resp = try JSONDecoder().decode(PayoutsResponse.self, from: data)
            payouts = resp.payouts
            payoutAvailableAgorot = resp.availableAgorot
        } catch { dbg("loadPayouts: \(error)") }
    }

    /// Admin-only: record that a sitter was paid out (disbursed offline).
    @discardableResult
    func recordPayout(sitterId: String, amountAgorot: Int, method: String,
                      reference: String?, note: String?) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        do {
            _ = try await call(path: "record-payout", method: "POST", body: [
                "sitterId": sitterId, "amountAgorot": amountAgorot, "method": method,
                "reference": reference as Any, "note": note as Any,
            ])
            return true
        } catch {
            lastError = (error as? PaymentError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Refund a charge (full if amountAgorot is nil). Owner-of-record or admin.
    @discardableResult
    func refund(transactionId: String, amountAgorot: Int?) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        do {
            var body: [String: Any] = ["transactionId": transactionId]
            if let amountAgorot { body["amountAgorot"] = amountAgorot }
            _ = try await call(path: "refund", method: "POST", body: body)
            return true
        } catch {
            lastError = (error as? PaymentError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// The VAT-breakdown receipt for a transaction, if one was issued.
    func loadReceipt(transactionId: String) async -> Receipt? {
        guard PaymentConfig.isConfigured else { return nil }
        do {
            let data = try await call(path: "receipts?transactionId=\(transactionId)", method: "GET", body: nil)
            return try JSONDecoder().decode(ReceiptResponse.self, from: data).receipt
        } catch { dbg("loadReceipt: \(error)"); return nil }
    }

    private struct MethodsResponse: Decodable { let methods: [PaymentMethod] }

    // MARK: - HTTP

    private func call(path: String, method: String, body: [String: Any]?,
                      requireAuth: Bool = true) async throws -> Data {
        guard PaymentConfig.isConfigured, let url = URL(string: "\(PaymentConfig.functionsBaseURL)/\(path)") else {
            throw PaymentError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(PaymentConfig.anonKey, forHTTPHeaderField: "apikey")
        if requireAuth {
            guard let token = try await Auth.auth().currentUser?.getIDToken() else {
                throw PaymentError.notAuthenticated
            }
            request.setValue(token, forHTTPHeaderField: "x-firebase-token")
        }
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
