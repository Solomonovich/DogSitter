import SwiftUI

/// The role-aware Payments hub, reached from the profile for BOTH roles.
/// Owner: total paid, saved cards, transactions (tap → receipt / refund).
/// Sitter: total earned, available-to-pay-out, payout history, transactions.
struct PaymentsHubView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme

    private var isOwner: Bool { appState.currentUserRole == .owner }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.lg) {
                if payments.activeProvider == "mock" { PaymentSandboxNotice() }

                balanceCard

                if isOwner {
                    ProfileLinkRow(icon: "creditcard.fill", title: "אמצעי תשלום") {
                        PaymentMethodsView()
                    }
                    .card()
                } else {
                    ProfileLinkRow(icon: "banknote.fill", title: "תשלומים שקיבלתי") {
                        PayoutHistoryView()
                    }
                    .card()
                }

                transactionsSection
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.lg)
        }
        .screenBackground()
        .navigationTitle(isOwner ? "התשלומים שלי" : "הארנק שלי")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = appState.currentUser?.id {
                payments.startListening(uid: uid, role: appState.currentUserRole)
                await payments.loadBalance()
                if !isOwner { await payments.loadPayouts() }
            }
        }
        .onDisappear { payments.stopListening() }
    }

    private var balanceCard: some View {
        let b = payments.balance
        return VStack(spacing: theme.spacing.xs) {
            Text(isOwner ? "סה״כ שולם" : "סה״כ הרווחת")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.color.textSecondary)
            Text(Money.formatILS(isOwner ? b.ownerChargedAgorot : b.sitterAccruedAgorot))
                .font(theme.typography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(theme.color.textPrimary)

            if isOwner {
                if b.ownerRefundedAgorot > 0 {
                    Text("מתוכו הוחזר: \(Money.formatILS(b.ownerRefundedAgorot))")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            } else {
                HStack(spacing: theme.spacing.xs) {
                    Text("זמין לתשלום:")
                        .font(theme.typography.subheadline)
                        .foregroundStyle(theme.color.textSecondary)
                    Text(Money.formatILS(b.sitterAvailableAgorot))
                        .font(theme.typography.bodyBold)
                        .foregroundStyle(theme.color.success)
                }
                .padding(.top, theme.spacing.xxs)
                Badge(text: "התשלום מתבצע ידנית ל-PayBox / ביט", kind: .warning)
                    .padding(.top, theme.spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.spacing.md)
        .card()
    }

    @ViewBuilder private var transactionsSection: some View {
        if payments.transactions.isEmpty {
            EmptyStateView(
                icon: "creditcard",
                title: "אין עדיין תשלומים",
                message: isOwner
                    ? "תשלומים יופיעו כאן לאחר שירותים שהושלמו."
                    : "הרווחים יופיעו כאן לאחר שתשלים שירותים."
            )
            .padding(.top, theme.spacing.xl)
        } else {
            VStack(spacing: theme.spacing.sm) {
                ForEach(payments.transactions) { tx in
                    if tx.paymentStatus == .succeeded {
                        NavigationLink { ReceiptView(transaction: tx) } label: {
                            PaymentTransactionRow(tx: tx)
                        }
                        .buttonStyle(.plain)
                    } else {
                        PaymentTransactionRow(tx: tx)
                    }
                }
            }
        }
    }
}

struct PaymentTransactionRow: View {
    @Environment(\.theme) private var theme
    let tx: PaymentTransaction

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: tx.paymentStatus == .refunded ? "arrow.uturn.left.circle.fill" : "pawprint.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(tx.needsAttention ? theme.color.error : theme.color.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.text ?? "תשלום עבור שירות")
                    .font(theme.typography.body)
                    .foregroundStyle(theme.color.textPrimary)
                if let date = tx.createdAt?.dateValue() {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(tx.formattedAmount)
                    .font(theme.typography.bodyBold)
                    .foregroundStyle(tx.amountAgorot > 0 ? theme.color.success : theme.color.textSecondary)
                statusBadge
            }
        }
        .padding(theme.spacing.md)
        .card()
    }

    private var statusBadge: Badge {
        switch tx.paymentStatus {
        case .succeeded: return Badge(text: tx.paymentStatus.displayName, kind: .success)
        case .failed:    return Badge(text: tx.paymentStatus.displayName, kind: .error)
        case .refunded:  return Badge(text: tx.paymentStatus.displayName, kind: .neutral)
        case .pending:   return Badge(text: tx.paymentStatus.displayName, kind: .warning)
        }
    }
}

/// Shown while the payment backend is on the mock rail (no real charges).
struct PaymentSandboxNotice: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "hammer.fill")
                .foregroundStyle(theme.color.warning)
            Text("התשלומים במצב בדיקה — לא מתבצע חיוב אמיתי.")
                .font(theme.typography.footnote)
                .foregroundStyle(theme.color.textSecondary)
            Spacer()
        }
        .padding(theme.spacing.md)
        .background(theme.color.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
    }
}
