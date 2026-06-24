import SwiftUI

/// Shared building blocks for the redesigned messages experience.
/// All visuals come from the design system (ProfileAvatar, Badge, theme tokens),
/// so the appearance settings (text size, roundness, avatar shape, gradient bg)
/// apply here automatically.

// MARK: - Inbox row

/// One conversation row: avatar · name · optional subtitle · last-message preview · time · status.
/// Bare (no card background) so callers wrap it — sitter rows get their own card,
/// owner rows sit inside a per-post group card.
struct ChatInboxRow: View {
    @Environment(\.theme) private var theme
    let name: String
    let photoURL: String?
    var subtitle: String? = nil      // e.g. pet names
    let preview: String
    let time: Date?
    var isUnread: Bool = false
    var isApproved: Bool = false

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            ProfileAvatar(photoURL: photoURL, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(theme.typography.headline)
                    .fontWeight(isUnread ? .bold : .semibold)
                    .foregroundStyle(theme.color.textPrimary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.color.accent)
                        .lineLimit(1)
                }

                Text(preview)
                    .font(theme.typography.subheadline)
                    .fontWeight(isUnread ? .semibold : .regular)
                    .foregroundStyle(isUnread ? theme.color.textPrimary : theme.color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: theme.spacing.xs)

            VStack(alignment: .trailing, spacing: theme.spacing.xxs) {
                if let time {
                    Text(ChatTime.inboxTimestamp(time))
                        .font(theme.typography.caption)
                        .foregroundStyle(isUnread ? theme.color.accent : theme.color.textSecondary)
                }
                if isUnread {
                    Circle()
                        .fill(theme.color.accent)
                        .frame(width: 10, height: 10)
                } else if isApproved {
                    Badge(text: "אושר", kind: .success, systemImage: "checkmark")
                }
            }
        }
        .padding(theme.spacing.sm)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Day separator

/// Centered pill marking a day break inside a conversation.
struct DateSeparator: View {
    @Environment(\.theme) private var theme
    let date: Date

    var body: some View {
        Text(ChatTime.daySeparator(date))
            .font(theme.typography.caption)
            .foregroundStyle(theme.color.textSecondary)
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, theme.spacing.xxs)
            .background(theme.color.surfaceSecondary)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.xxs)
    }
}

// MARK: - Booking summary chip

/// Compact, informational summary of the post a conversation is about:
/// pets · sitting type · date range · pay. Surfaces data already on the chat's post.
struct BookingSummaryChip: View {
    @Environment(\.theme) private var theme
    let post: Post?
    let pets: [Pet]

    var body: some View {
        if let post {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "pawprint.fill")
                    .foregroundStyle(theme.color.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline(post))
                        .font(theme.typography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.color.textPrimary)
                        .lineLimit(1)
                    Text(dateRange(post))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: theme.spacing.xs)

                Text(pay(post))
                    .font(theme.typography.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(theme.color.success)
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
            .background(theme.color.surface)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                    .stroke(theme.color.separator, lineWidth: 1)
            )
            .padding(.horizontal, theme.spacing.md)
            .padding(.top, theme.spacing.xs)
        }
    }

    private func headline(_ post: Post) -> String {
        let names = pets.map { $0.name }.joined(separator: ", ")
        let type = post.mappedPostType.displayName
        return names.isEmpty ? type : "\(names) · \(type)"
    }

    private func dateRange(_ post: Post) -> String {
        let start = post.startDate.dateValue().formatted(date: .abbreviated, time: .omitted)
        let end = post.endDate.dateValue().formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }

    private func pay(_ post: Post) -> String {
        return "₪\(Int(post.payAmount)) \(post.mappedPostType.perUnitLabel)"
    }
}
