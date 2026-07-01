import SwiftUI

/// A transaction's receipt (VAT breakdown) plus, for the owner, a refund action.
struct ReceiptView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme

    let transaction: PaymentTransaction

    @State private var receipt: Receipt?
    @State private var loading = true
    @State private var showRefundConfirm = false
    @State private var refunding = false
    @State private var resultMessage: String?

    private var isOwner: Bool { appState.currentUserRole == .owner }
    private var txId: String { transaction.transactionId ?? transaction.id ?? "" }
    private var canRefund: Bool { isOwner && transaction.paymentStatus == .succeeded && transaction.amountAgorot > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.lg) {
                headerCard
                if loading {
                    ProgressView().padding(.top, theme.spacing.lg)
                } else if let receipt {
                    breakdownCard(receipt)
                }
                if canRefund { refundButton }
                if let resultMessage {
                    Text(resultMessage)
                        .font(theme.typography.footnote)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.lg)
        }
        .screenBackground()
        .navigationTitle("פרטי תשלום")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            receipt = await payments.loadReceipt(transactionId: txId)
            loading = false
        }
        .confirmationDialog("החזר תשלום", isPresented: $showRefundConfirm, titleVisibility: .visible) {
            Button("בצע החזר מלא", role: .destructive) { Task { await doRefund() } }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("יבוצע החזר מלא של \(transaction.formattedAmount) לבעל הכלב.")
        }
    }

    private var headerCard: some View {
        VStack(spacing: theme.spacing.xs) {
            Text(transaction.text ?? "תשלום")
                .font(theme.typography.body)
                .foregroundStyle(theme.color.textSecondary)
                .multilineTextAlignment(.center)
            Text(transaction.formattedAmount)
                .font(theme.typography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(theme.color.textPrimary)
            Badge(text: transaction.paymentStatus.displayName,
                  kind: transaction.paymentStatus == .succeeded ? .success
                      : transaction.paymentStatus == .refunded ? .neutral : .error)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.spacing.md)
        .card()
    }

    private func breakdownCard(_ r: Receipt) -> some View {
        VStack(spacing: theme.spacing.sm) {
            row("מספר קבלה", r.number)
            Divider().overlay(theme.color.separator)
            row("לפני מע״מ", r.formattedNet)
            row("מע״מ (\(r.vatRatePercent)%)", r.formattedVat)
            Divider().overlay(theme.color.separator)
            row("סה״כ", r.formattedGross, bold: true)
        }
        .padding(theme.spacing.md)
        .card()
    }

    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.color.textSecondary)
            Spacer()
            Text(value)
                .font(bold ? theme.typography.bodyBold : theme.typography.body)
                .foregroundStyle(theme.color.textPrimary)
        }
    }

    private var refundButton: some View {
        Button(refunding ? "מבצע החזר…" : "החזר תשלום") { showRefundConfirm = true }
            .buttonStyle(DestructiveButtonStyle())
            .disabled(refunding)
    }

    private func doRefund() async {
        refunding = true
        defer { refunding = false }
        let ok = await payments.refund(transactionId: txId, amountAgorot: nil)
        resultMessage = ok
            ? "ההחזר בוצע. השינוי יופיע בהיסטוריית התשלומים."
            : (payments.lastError ?? "ההחזר נכשל")
    }
}
