import SwiftUI
import UIKit
import StripePaymentsUI
import StripePayments

/// A plain Stripe card-entry form (STPPaymentCardTextField) that confirms the
/// SetupIntent directly. Used INSTEAD of PaymentSheet, which fails to render on
/// iOS 26. No Link, no PaymentSheet — just card in, card saved.
struct StripeCardFormSheet: View {
    let clientSecret: String
    let setupIntentId: String
    var onSaved: (Bool) -> Void

    @EnvironmentObject private var payments: PaymentService
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var cardParams: STPPaymentMethodParams?
    @State private var isValid = false
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: theme.spacing.lg) {
                    Text("הזן את פרטי הכרטיס. החיוב יתבצע רק לאחר השירות.")
                        .font(theme.typography.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                        .multilineTextAlignment(.center)

                    StripeCardField(params: $cardParams, isValid: $isValid)
                        .frame(height: 48)
                        .padding(.horizontal, theme.spacing.sm)
                        .background(theme.color.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                                .stroke(theme.color.separator, lineWidth: 1)
                        )

                    if let errorText {
                        Text(errorText)
                            .font(theme.typography.footnote)
                            .foregroundStyle(theme.color.error)
                            .multilineTextAlignment(.center)
                    }

                    Button(submitting ? "שומר…" : "שמור כרטיס") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isValid || submitting)
                }
                .padding(theme.spacing.lg)
            }
            .screenBackground()
            .navigationTitle("הוספת כרטיס")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let cardParams else { return }
        submitting = true
        errorText = nil

        let confirmParams = STPSetupIntentConfirmParams(clientSecret: clientSecret)
        confirmParams.paymentMethodParams = cardParams
        let authContext = CardAuthContext()

        STPPaymentHandler.shared().confirmSetupIntent(confirmParams, with: authContext) { status, _, error in
            Task { @MainActor in
                switch status {
                case .succeeded:
                    let ok = await payments.finalizeCard(ref: setupIntentId, makeDefault: true)
                    submitting = false
                    if ok { onSaved(true); dismiss() }
                    else { errorText = payments.lastError ?? "שמירת הכרטיס נכשלה" }
                case .canceled:
                    submitting = false
                case .failed:
                    submitting = false
                    errorText = error?.localizedDescription ?? "אימות הכרטיס נכשל"
                @unknown default:
                    submitting = false
                }
            }
        }
    }
}

/// Bridges Stripe's UIKit card field into SwiftUI, publishing validity + params.
struct StripeCardField: UIViewRepresentable {
    @Binding var params: STPPaymentMethodParams?
    @Binding var isValid: Bool

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let field = STPPaymentCardTextField()
        field.delegate = context.coordinator
        field.postalCodeEntryEnabled = false
        return field
    }

    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        let parent: StripeCardField
        init(_ parent: StripeCardField) { self.parent = parent }

        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            parent.isValid = textField.isValid
            parent.params = textField.isValid ? textField.paymentMethodParams : nil
        }
    }
}

/// 3DS authentication context. Card saves (test cards) don't present anything;
/// real 3DS cards present from the top view controller.
final class CardAuthContext: NSObject, STPAuthenticationContext {
    // Stripe calls this on the main thread; assumeIsolated lets us reach the
    // @MainActor top-view-controller helper from this nonisolated @objc method.
    func authenticationPresentingViewController() -> UIViewController {
        MainActor.assumeIsolated {
            CardCaptureCoordinator.topViewController() ?? UIViewController()
        }
    }
}
