import SwiftUI

/// The sitter's payout history (manual disbursements via PayBox Young / Bit) and
/// their available-to-pay-out total. Read-only — payouts are recorded by an admin.
struct PayoutHistoryView: View {
    @EnvironmentObject var payments: PaymentService
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.lg) {
                availableCard

                if payments.payouts.isEmpty {
                    EmptyStateView(
                        icon: "banknote",
                        title: "אין עדיין תשלומים",
                        message: "כשנעביר לך תשלום (PayBox / ביט) הוא יופיע כאן."
                    )
                    .padding(.top, theme.spacing.xl)
                } else {
                    VStack(spacing: theme.spacing.sm) {
                        ForEach(payments.payouts) { payout in
                            PayoutRow(payout: payout)
                        }
                    }
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.lg)
        }
        .screenBackground()
        .navigationTitle("תשלומים שקיבלתי")
        .navigationBarTitleDisplayMode(.inline)
        .task { await payments.loadPayouts() }
    }

    private var availableCard: some View {
        VStack(spacing: theme.spacing.xs) {
            Text("זמין לתשלום")
                .font(theme.typography.subheadline)
                .foregroundStyle(theme.color.textSecondary)
            Text(Money.formatILS(payments.payoutAvailableAgorot))
                .font(theme.typography.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(theme.color.success)
            Text("התשלום מתבצע ידנית לארנק PayBox Young / ביט שלך.")
                .font(theme.typography.caption)
                .foregroundStyle(theme.color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.spacing.md)
        .card()
    }
}

struct PayoutRow: View {
    @Environment(\.theme) private var theme
    let payout: Payout

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(theme.color.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(payout.methodLabel)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.color.textPrimary)
                if let note = payout.note, !note.isEmpty {
                    Text(note)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            Spacer()
            Text(payout.formattedAmount)
                .font(theme.typography.bodyBold)
                .foregroundStyle(theme.color.textPrimary)
        }
        .padding(theme.spacing.md)
        .card()
    }
}
