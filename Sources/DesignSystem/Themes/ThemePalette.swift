import SwiftUI

/// User-selectable color palettes. Persisted via @AppStorage in ThemeManager.
/// Each palette reuses the light/dark base theme and overrides only the accent
/// color + brand gradient, so surfaces/text stay consistent and legible.
enum ThemePalette: String, CaseIterable, Codable, Identifiable {
    case classic
    case ocean
    case sunset
    case forest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "כחול קלאסי"
        case .ocean:   return "אוקיינוס"
        case .sunset:  return "שקיעה"
        case .forest:  return "יער"
        }
    }

    func accent(dark: Bool) -> Color {
        switch self {
        case .classic: return dark ? Color(hex: "#5B9DE0") : Color(hex: "#4A90D9")
        case .ocean:   return dark ? Color(hex: "#22D3C5") : Color(hex: "#0E9AA7")
        case .sunset:  return dark ? Color(hex: "#FB923C") : Color(hex: "#F2761B")
        case .forest:  return dark ? Color(hex: "#4ADE80") : Color(hex: "#2E9E5B")
        }
    }

    func accentGradient(dark: Bool) -> [Color] {
        switch self {
        case .classic: return dark ? [Color(hex: "#5B9DE0"), Color(hex: "#4FD0E0")]
                                   : [Color(hex: "#4A90D9"), Color(hex: "#42C8D9")]
        case .ocean:   return dark ? [Color(hex: "#22D3C5"), Color(hex: "#3B82F6")]
                                   : [Color(hex: "#0E9AA7"), Color(hex: "#2563EB")]
        case .sunset:  return dark ? [Color(hex: "#FB923C"), Color(hex: "#F43F5E")]
                                   : [Color(hex: "#F2761B"), Color(hex: "#E5484D")]
        case .forest:  return dark ? [Color(hex: "#4ADE80"), Color(hex: "#22D3C5")]
                                   : [Color(hex: "#2E9E5B"), Color(hex: "#0E9AA7")]
        }
    }

    /// Resolves a full Theme for the given color scheme.
    func theme(for scheme: ColorScheme) -> Theme {
        let dark = scheme == .dark
        let base = dark ? Theme.darkClassic : Theme.lightClassic
        return base.withAccent(accent(dark: dark), gradient: accentGradient(dark: dark))
    }
}
