import SwiftUI

/// Semantic color tokens for the app. Every view should pull colors from here
/// rather than using hardcoded `Color.blue`, `Color(hex:)`, etc.
struct ColorTokens: Equatable {
    // Surfaces
    var background: Color          // screen background
    var surface: Color             // cards / sheets / rows
    var surfaceSecondary: Color    // input fields / chips / grouped fills
    // Text
    var textPrimary: Color
    var textSecondary: Color
    var textOnAccent: Color        // text/icons on top of the accent color
    // Brand / interactive
    var accent: Color
    var accentGradient: [Color]    // brand gradient (blue → cyan by default)
    // Status
    var success: Color
    var warning: Color
    var error: Color
    // Lines
    var separator: Color
}

/// The full design theme: colors plus the shared token scales.
struct Theme: Equatable {
    var color: ColorTokens
    var typography: Typography = .standard
    var spacing: Spacing = .standard
    var radius: Radius = .standard
    var elevation: Elevation = .standard
}
