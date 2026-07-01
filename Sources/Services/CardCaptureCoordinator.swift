import Foundation
import UIKit
import OSLog
import StripePaymentSheet

extension Notification.Name {
    /// Posted when the app reopens on the Grow hosted-page return (dogsitter://pay).
    static let growPaymentReturn = Notification.Name("growPaymentReturn")
}

/// Prepares card capture across rails. For Stripe it builds a ready `PaymentSheet`
/// that the SwiftUI layer presents NATIVELY via the `.paymentSheet` modifier —
/// presenting Stripe's sheet from the top view controller faults on iOS 26, so we
/// stay inside SwiftUI's presentation lifecycle. Mock → sandbox form; Grow → hosted
/// page via ASWebAuthenticationSession (which manages its own presentation).
@MainActor
final class CardCaptureCoordinator: ObservableObject {
    static let shared = CardCaptureCoordinator()
    private init() {}

    enum Prepared {
        case stripeCard(clientSecret: String, setupIntentId: String)
        case needsManualEntry
        case grow(URL, processToken: String)
        case failed(String)
    }

    private let payments = PaymentService.shared
    private let logger = Logger(subsystem: "com.shaqed.dogsitter", category: "CardCapture")
    private func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        print("[CardCapture] \(message)")
    }

    /// Fetch a setup session and prepare the rail-appropriate capture.
    func prepare() async -> Prepared {
        log("begin")
        do {
            let apiVersion = STPAPIClient.apiVersion
            log("requesting setup session (SDK apiVersion=\(apiVersion))")
            let session = try await payments.beginCardSetup(apiVersion: apiVersion)
            log("got session kind=\(session.kind)")

            switch session.kind {
            case "stripe_setup_intent":
                guard let clientSecret = session.setupIntentClientSecret else {
                    log("stripe session missing client secret")
                    return .failed("הגדרת התשלום נכשלה")
                }
                if let pk = session.publishableKey, !pk.isEmpty {
                    STPAPIClient.shared.publishableKey = pk
                }
                let setupIntentId = clientSecret.components(separatedBy: "_secret_").first ?? clientSecret
                log("stripe card form prepared (si=\(setupIntentId.prefix(11)))")
                return .stripeCard(clientSecret: clientSecret, setupIntentId: setupIntentId)

            case "mock_manual":
                return .needsManualEntry

            case "grow_hosted_page":
                guard let urlString = session.hostedPageUrl, let url = URL(string: urlString) else {
                    return .failed("הגדרת התשלום נכשלה")
                }
                return .grow(url, processToken: session.processToken ?? "")

            default:
                return .failed("אופן הוספת הכרטיס אינו נתמך")
            }
        } catch {
            log("setup-card failed: \(error)")
            return .failed((error as? PaymentError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Grow hosted-page capture. ASWebAuthenticationSession owns its presentation.
    func completeGrow(url: URL, processToken: String) async -> Bool {
        let callback = await GrowWebAuth.present(url: url)
        guard callback != nil else { return false }
        return await payments.finalizeCard(ref: processToken, makeDefault: true)
    }

    /// Anchor for ASWebAuthenticationSession (Grow) — not used for PaymentSheet.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
