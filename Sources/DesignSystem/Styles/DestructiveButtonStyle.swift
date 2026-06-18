import SwiftUI

/// Destructive action: tinted error background with error-colored text.
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.headline)
            .foregroundStyle(theme.color.error)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, theme.spacing.md)
            .padding(.horizontal, theme.spacing.lg)
            .background(theme.color.error.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
