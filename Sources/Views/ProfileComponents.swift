import SwiftUI

/// Shared building blocks for the unified profile layout (sitter + owner).
/// Visual only — every action is delegated back to the host screen via closures
/// or navigation, so the existing behavior is preserved untouched.

// MARK: - Header

/// Avatar + identity + "edit profile" entry point, wrapped in a card.
struct ProfileHeaderCard: View {
    @Environment(\.theme) private var theme
    let user: User

    var body: some View {
        VStack(spacing: theme.spacing.sm) {
            ProfileAvatar(photoURL: user.photoURL, size: 96)

            VStack(spacing: theme.spacing.xxs) {
                Text(user.name)
                    .font(theme.typography.title)
                    .foregroundStyle(theme.color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(user.username)
                    .font(theme.typography.subheadline)
                    .foregroundStyle(theme.color.textSecondary)

                if let address = user.address, !address.isEmpty {
                    detailRow(icon: "mappin.and.ellipse", text: address)
                }
                // Phone is a sitter-only field (kept from the original profile).
                if user.role == "sitter", let phone = user.phone, !phone.isEmpty {
                    detailRow(icon: "phone.fill", text: phone)
                }
            }

            NavigationLink(destination: EditProfileView()) {
                Text("ערוך פרופיל")
                    .font(theme.typography.subheadline.weight(.semibold))
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.xs)
                    .background(theme.color.accent)
                    .foregroundStyle(theme.color.textOnAccent)
                    .clipShape(Capsule())
            }
            .padding(.top, theme.spacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: theme.spacing.xs) {
            Image(systemName: icon)
                .font(theme.typography.footnote)
            Text(text)
                .font(theme.typography.subheadline)
        }
        .foregroundStyle(theme.color.textSecondary)
    }
}

// MARK: - Settings

/// A tappable icon + title + chevron row used inside settings cards.
struct ProfileLinkRow<Destination: View>: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    let destination: () -> Destination

    init(icon: String, title: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.icon = icon
        self.title = title
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: theme.spacing.md) {
                Image(systemName: icon)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.color.accent)
                    .frame(width: 26)
                Text(title)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.color.textPrimary)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(theme.typography.footnote)
                    .foregroundStyle(theme.color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Card holding the appearance entry point (room to grow with more visual links).
struct ProfileSettingsCard: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ProfileLinkRow(icon: "paintbrush.fill", title: "מראה ותצוגה") {
                ThemePickerView()
            }

            Divider().overlay(theme.color.separator)
                .padding(.vertical, theme.spacing.xs)

            ProfileLinkRow(icon: "creditcard.fill", title: "תשלומים") {
                PaymentHistoryView()
            }
        }
        .card()
    }
}

// MARK: - Account actions

/// Log out + delete account, as two clearly-tinted rows in a card.
/// The host screen owns the actual logout call and the delete-confirmation alert.
struct AccountActionsCard: View {
    @Environment(\.theme) private var theme
    let logout: () -> Void
    let deleteTapped: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: logout) {
                actionRow(icon: "rectangle.portrait.and.arrow.right",
                          iconColor: theme.color.accent,
                          title: "התנתק",
                          titleColor: theme.color.textPrimary)
            }
            .buttonStyle(.plain)

            Divider().overlay(theme.color.separator)
                .padding(.vertical, theme.spacing.xs)

            // F-27: account deletion (required for App Store compliance).
            Button(action: deleteTapped) {
                actionRow(icon: "trash.fill",
                          iconColor: theme.color.error,
                          title: "מחק חשבון",
                          titleColor: theme.color.error)
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func actionRow(icon: String, iconColor: Color, title: String, titleColor: Color) -> some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(theme.typography.body)
                .foregroundStyle(iconColor)
                .frame(width: 26)
            Text(title)
                .font(theme.typography.body)
                .foregroundStyle(titleColor)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, theme.spacing.xxs)
    }
}
