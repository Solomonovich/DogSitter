import SwiftUI

extension Theme {
    /// Light base theme (Classic Blue brand).
    static let lightClassic = Theme(
        color: ColorTokens(
            background:       Color(hex: "#F4F6FA"),
            surface:          .white,
            surfaceSecondary: Color(hex: "#EDF1F6"),
            textPrimary:      Color(hex: "#1A1D29"),
            textSecondary:    Color(hex: "#6B7280"),
            textOnAccent:     .white,
            accent:           Color(hex: "#4A90D9"),
            accentGradient:   [Color(hex: "#4A90D9"), Color(hex: "#42C8D9")],
            success:          Color(hex: "#2E9E5B"),
            warning:          Color(hex: "#E68A00"),
            error:            Color(hex: "#E53935"),
            separator:        Color(hex: "#E2E6EC")
        )
    )

    /// Dark base theme (Classic Blue brand).
    static let darkClassic = Theme(
        color: ColorTokens(
            background:       Color(hex: "#0E1116"),
            surface:          Color(hex: "#1A1F27"),
            surfaceSecondary: Color(hex: "#252B35"),
            textPrimary:      Color(hex: "#F4F6FA"),
            textSecondary:    Color(hex: "#9AA4B2"),
            textOnAccent:     .white,
            accent:           Color(hex: "#5B9DE0"),
            accentGradient:   [Color(hex: "#5B9DE0"), Color(hex: "#4FD0E0")],
            success:          Color(hex: "#5CC98A"),
            warning:          Color(hex: "#FFB74D"),
            error:            Color(hex: "#EF5350"),
            separator:        Color(hex: "#2C333D")
        )
    )

    /// Returns a copy of this theme with a different accent color + brand gradient.
    func withAccent(_ accent: Color, gradient: [Color]) -> Theme {
        var copy = self
        copy.color.accent = accent
        copy.color.accentGradient = gradient
        return copy
    }
}
