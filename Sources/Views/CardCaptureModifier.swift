import SwiftUI

/// Attaches card capture to any view. Flip `trigger` to true to start; `onFinished`
/// fires with whether a card was saved. Stripe uses our own card-field form (a
/// standard SwiftUI sheet — reliable on iOS 26, unlike PaymentSheet); the mock rail
/// shows the sandbox form; Grow uses its hosted-page web-auth session.
struct CardCaptureModifier: ViewModifier {
    @Binding var trigger: Bool
    var onFinished: (Bool) -> Void

    // One item-driven sheet (never two isPresented sheets — they blank each other out).
    private enum ActiveSheet: Identifiable {
        case stripe(StripeCardInfo)
        case sandbox
        var id: String { if case .stripe = self { return "stripe" } else { return "sandbox" } }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var busy = false
    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, active in
                if active { trigger = false; start() }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .stripe(let card):
                    StripeCardFormSheet(clientSecret: card.clientSecret,
                                        setupIntentId: card.setupIntentId,
                                        onSaved: { onFinished($0) })
                case .sandbox:
                    SandboxCardSheet(onSaved: { onFinished(true) })
                }
            }
            .alert("שגיאה", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } })) {
                Button("סגור", role: .cancel) { errorText = nil }
            } message: { Text(errorText ?? "") }
    }

    private func start() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            let prepared = await CardCaptureCoordinator.shared.prepare()
            busy = false
            switch prepared {
            case .stripeCard(let clientSecret, let setupIntentId):
                activeSheet = .stripe(StripeCardInfo(clientSecret: clientSecret, setupIntentId: setupIntentId))
            case .needsManualEntry:
                activeSheet = .sandbox
            case .grow(let url, let token):
                let ok = await CardCaptureCoordinator.shared.completeGrow(url: url, processToken: token)
                onFinished(ok)
            case .failed(let message):
                errorText = message
                onFinished(false)
            }
        }
    }
}

struct StripeCardInfo {
    let clientSecret: String
    let setupIntentId: String
}

extension View {
    /// Start card capture by flipping `trigger` to true.
    func cardCapture(trigger: Binding<Bool>, onFinished: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(CardCaptureModifier(trigger: trigger, onFinished: onFinished))
    }
}
