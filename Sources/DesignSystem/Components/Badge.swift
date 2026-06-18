import SwiftUI

enum BadgeKind {
    case success, warning, error, neutral, accent
}

/// A small status pill (tinted capsule). Replaces ad-hoc `Capsule()` + color usage.
struct Badge: View {
    @Environment(\.theme) private var theme
    let text: String
    var kind: BadgeKind = .neutral
    var systemImage: String? = nil

    private var tint: Color {
        switch kind {
        case .success: return theme.color.success
        case .warning: return theme.color.warning
        case .error:   return theme.color.error
        case .accent:  return theme.color.accent
        case .neutral: return theme.color.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(theme.typography.captionBold)
        .foregroundStyle(tint)
        .padding(.horizontal, theme.spacing.sm)
        .padding(.vertical, theme.spacing.xxs)
        .background(tint.opacity(0.15))
        .clipShape(Capsule())
    }
}
