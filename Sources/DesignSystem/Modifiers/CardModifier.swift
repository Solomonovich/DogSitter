import SwiftUI

/// Standard card surface: padding + themed surface background + rounded corners + soft shadow.
struct CardModifier: ViewModifier {
    @Environment(\.theme) private var theme
    var padding: CGFloat?
    var cornerRadius: CGFloat?
    var shadow: AppShadow?

    func body(content: Content) -> some View {
        content
            .padding(padding ?? theme.spacing.md)
            .background(theme.color.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? theme.radius.card, style: .continuous))
            .elevation(shadow ?? theme.elevation.card)
    }
}

extension View {
    /// Wraps the view in a standard themed card.
    func card(padding: CGFloat? = nil, cornerRadius: CGFloat? = nil, shadow: AppShadow? = nil) -> some View {
        modifier(CardModifier(padding: padding, cornerRadius: cornerRadius, shadow: shadow))
    }
}
