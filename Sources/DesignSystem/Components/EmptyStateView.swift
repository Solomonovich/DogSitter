import SwiftUI

/// A friendly empty / placeholder state: icon, title, optional message, optional CTA.
struct EmptyStateView: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(theme.color.textSecondary.opacity(0.55))
            Text(title)
                .font(theme.typography.title3)
                .foregroundStyle(theme.color.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(theme.typography.subheadline)
                    .foregroundStyle(theme.color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                    .padding(.top, theme.spacing.xs)
            }
        }
        .padding(theme.spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
