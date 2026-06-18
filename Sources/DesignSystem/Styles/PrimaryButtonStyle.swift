import SwiftUI

/// Primary call-to-action: brand gradient fill, white text, rounded, soft shadow.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.typography.headline)
            .foregroundStyle(theme.color.textOnAccent)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, theme.spacing.md)
            .padding(.horizontal, theme.spacing.lg)
            .background(
                LinearGradient(colors: theme.color.accentGradient,
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
            .elevation(isEnabled ? theme.elevation.card : theme.elevation.none)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
