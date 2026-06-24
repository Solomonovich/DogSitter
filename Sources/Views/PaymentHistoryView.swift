import SwiftUI

/// Role-aware wallet: owners see what they've been charged, sitters see accrued
/// earnings (collect-only — not yet paid out). History is read live from Firestore
/// via PaymentService; the running total comes from the get-balance function.
struct PaymentHistoryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme

    private var isOwner: Bool { appState.currentUserRole == .owner }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.lg) {
                if !PaymentConfig.isConfigured { PaymentSandboxNotice() }

                balanceCard

                if isOwner {
                    ProfileLinkRow(icon: "creditcard.fill", title: "אמצעי תשלום") {
                        PaymentMethodsView()
                    }
                    .card()
                }

                transactionsSection
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.lg)
        }
        .screenBackground()
        .navigationTitle(isOwner ? "התשלומים שלי" : "הרווחים שלי")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = appState.currentUser?.id {
                payments.startListening(uid: uid, role: appState.currentUserRole)
                await payments.loadBalance()
            }
        }
        .onDisappear { payments.stopListening() }
    }

    private var balanceCard: some View {
        let agorot = isOwner ? payments.balance.ownerChargedAgorot : payments.balance.sitterAccruedAgorot
        return VStack(spacing: theme.spacing.xs) {
            Text(isOwner ? "סה״כ שולם" : "סה״כ הרווחת")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.color.textSecondary)
            Text(Money.formatILS(agorot))
                .font(theme.typography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(theme.color.textPrimary)
            if !isOwner {
                Badge(text: "טרם הועבר לתשלום", kind: .warning)
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
                    ? "תשלומים יופיעו כאן לאחר שהליכות יושלמו."
                    : "הרווחים יופיעו כאן לאחר שתשלים הליכות."
            )
            .padding(.top, theme.spacing.xl)
        } else {
            VStack(spacing: theme.spacing.sm) {
                ForEach(payments.transactions) { tx in
                    PaymentTransactionRow(tx: tx)
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
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(theme.color.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.text ?? "תשלום עבור הליכה")
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

/// Shown while the payment backend isn't wired to a real processor.
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
