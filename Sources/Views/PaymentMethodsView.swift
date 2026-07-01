import SwiftUI

/// Manage saved cards. Capture is real and tokenized (Stripe PaymentSheet via
/// CardCaptureCoordinator); on the sandbox/mock rail a simple form collects only a
/// last4. No PAN ever reaches our backend.
struct PaymentMethodsView: View {
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme
    @State private var triggerCapture = false
    @State private var capturing = false

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.lg) {
                if payments.activeProvider == "mock" { PaymentSandboxNotice() }

                if payments.paymentMethods.isEmpty {
                    EmptyStateView(
                        icon: "creditcard",
                        title: "אין אמצעי תשלום",
                        message: "הוסף כרטיס כדי לשלם עבור הליכות ואירוחים.",
                        actionTitle: capturing ? "מוסיף…" : "הוסף כרטיס",
                        action: { addCard() }
                    )
                    .padding(.top, theme.spacing.xl)
                } else {
                    VStack(spacing: theme.spacing.sm) {
                        ForEach(payments.paymentMethods) { method in
                            PaymentMethodRow(method: method)
                        }
                    }
                    Button(capturing ? "מוסיף…" : "הוסף כרטיס") { addCard() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(capturing)
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.lg)
        }
        .screenBackground()
        .navigationTitle("אמצעי תשלום")
        .navigationBarTitleDisplayMode(.inline)
        .task { await payments.loadPaymentMethods() }
        .cardCapture(trigger: $triggerCapture) { _ in capturing = false }
    }

    private func addCard() {
        guard !capturing else { return }
        capturing = true
        triggerCapture = true
    }
}

struct PaymentMethodRow: View {
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme
    let method: PaymentMethod

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 26))
                .foregroundStyle(theme.color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(method.brand.capitalized)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.color.textPrimary)
                HStack(spacing: theme.spacing.xs) {
                    Text(method.maskedNumber)
                    if let exp = method.expiryLabel { Text("· \(exp)") }
                }
                .font(theme.typography.caption)
                .foregroundStyle(theme.color.textSecondary)
            }
            Spacer()
            if method.isDefault {
                Badge(text: "ברירת מחדל", kind: .accent)
            }
            Menu {
                if !method.isDefault {
                    Button("הגדר כברירת מחדל") {
                        Task { await payments.setDefaultPaymentMethod(id: method.id) }
                    }
                }
                Button("מחק כרטיס", role: .destructive) {
                    Task { await payments.deletePaymentMethod(id: method.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .padding(theme.spacing.md)
        .card()
    }
}

/// Sandbox-only card form (mock rail). Collects a fake card number and keeps only
/// the last4. Never used on a real rail — Stripe capture goes through PaymentSheet.
struct SandboxCardSheet: View {
    var onSaved: () -> Void = {}
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var number = ""
    @State private var expiry = ""
    @State private var cvv = ""
    @State private var makeDefault = true
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: theme.spacing.md) {
                    Text("הכרטיס נשמר במצב בדיקה בלבד — אין להזין פרטי כרטיס אמיתיים.")
                        .font(theme.typography.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                        .multilineTextAlignment(.center)

                    ThemedInputField(icon: "creditcard", placeholder: "מספר כרטיס",
                                     text: $number, keyboard: .numberPad)
                    HStack(spacing: theme.spacing.md) {
                        ThemedInputField(icon: "calendar", placeholder: "MM/YY",
                                         text: $expiry, keyboard: .numbersAndPunctuation)
                        ThemedInputField(icon: "lock", placeholder: "CVV",
                                         text: $cvv, keyboard: .numberPad)
                    }
                    Toggle("הגדר כברירת מחדל", isOn: $makeDefault)
                        .tint(theme.color.accent)

                    if let errorText {
                        Text(errorText)
                            .font(theme.typography.footnote)
                            .foregroundStyle(theme.color.error)
                    }

                    Button(submitting ? "שומר…" : "שמור כרטיס") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(submitting || digits(number).count < 4)
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

    private func digits(_ s: String) -> String { s.filter(\.isNumber) }

    private func save() async {
        submitting = true
        defer { submitting = false }
        // The mock rail's finalizeSavedCard reads last4 from `ref`.
        let ok = await payments.finalizeCard(ref: String(digits(number).suffix(4)), makeDefault: makeDefault)
        if ok { onSaved(); dismiss() } else { errorText = payments.lastError ?? "שמירת הכרטיס נכשלה" }
    }
}
