import SwiftUI

/// Manage saved (mock) cards. SANDBOX ONLY — no real PAN is ever transmitted or
/// stored; the backend keeps just brand + last4 + a fake token.
struct PaymentMethodsView: View {
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme
    @State private var showAddCard = false

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.lg) {
                if !PaymentConfig.isConfigured { PaymentSandboxNotice() }

                if payments.paymentMethods.isEmpty {
                    EmptyStateView(
                        icon: "creditcard",
                        title: "אין אמצעי תשלום",
                        message: "הוסף כרטיס כדי לשלם עבור הליכות.",
                        actionTitle: "הוסף כרטיס",
                        action: { showAddCard = true }
                    )
                    .padding(.top, theme.spacing.xl)
                } else {
                    VStack(spacing: theme.spacing.sm) {
                        ForEach(payments.paymentMethods) { method in
                            PaymentMethodRow(method: method)
                        }
                    }
                    Button("הוסף כרטיס") { showAddCard = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.lg)
        }
        .screenBackground()
        .navigationTitle("אמצעי תשלום")
        .navigationBarTitleDisplayMode(.inline)
        .task { await payments.loadPaymentMethods() }
        .sheet(isPresented: $showAddCard) { AddCardSheet() }
    }
}

struct PaymentMethodRow: View {
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
                Text(method.maskedNumber)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
            Spacer()
            if method.isDefault {
                Badge(text: "ברירת מחדל", kind: .accent)
            }
        }
        .padding(theme.spacing.md)
        .card()
    }
}

/// Sandbox card-entry form. We only keep brand + last4 — the rest is discarded.
struct AddCardSheet: View {
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

    private func brand(for digits: String) -> String {
        switch digits.first {
        case "4": return "visa"
        case "5": return "mastercard"
        case "3": return "amex"
        default:  return "card"
        }
    }

    private func save() async {
        submitting = true
        defer { submitting = false }
        let d = digits(number)
        let ok = await payments.addPaymentMethod(
            last4: String(d.suffix(4)),
            brand: brand(for: d),
            makeDefault: makeDefault
        )
        if ok { dismiss() } else { errorText = payments.lastError ?? "שמירת הכרטיס נכשלה" }
    }
}
