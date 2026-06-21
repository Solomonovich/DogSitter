import SwiftUI

/// User-selectable VISUAL preferences (persisted via @AppStorage in ThemeManager).
/// Each one is composed into `ThemeManager.theme`, so it propagates app-wide through
/// `@Environment(\.theme)` without any per-view changes. Purely cosmetic — no behavior.

/// App-wide text size. Multiplies every typography token's point size.
enum TextSizePreference: String, CaseIterable, Codable, Identifiable {
    case small
    case standard
    case large
    case xLarge

    var id: String { rawValue }

    /// Multiplier applied to every font size in `Typography`.
    var scale: CGFloat {
        switch self {
        case .small:    return 0.9
        case .standard: return 1.0
        case .large:    return 1.12
        case .xLarge:   return 1.25
        }
    }

    var displayName: String {
        switch self {
        case .small:    return "קטן"
        case .standard: return "רגיל"
        case .large:    return "גדול"
        case .xLarge:   return "גדול מאוד"
        }
    }
}

/// App-wide corner roundness. Swaps the whole `Radius` scale.
enum CornerStyle: String, CaseIterable, Codable, Identifiable {
    case sharp
    case soft
    case rounded

    var id: String { rawValue }

    var radius: Radius {
        switch self {
        case .sharp:   return .sharp
        case .soft:    return .soft
        case .rounded: return .rounded
        }
    }

    var displayName: String {
        switch self {
        case .sharp:   return "חד"
        case .soft:    return "רך"
        case .rounded: return "מעוגל"
        }
    }

    /// Representative corner radius for the picker preview swatch.
    var sampleRadius: CGFloat {
        switch self {
        case .sharp:   return 2
        case .soft:    return 9
        case .rounded: return 16
        }
    }
}

/// Screen background fill style. Consumed by the `.screenBackground()` modifier.
enum BackgroundStyle: String, Codable, Equatable {
    case solid
    case gradient
}

/// Avatar clip shape used by `ProfileAvatar`.
enum AvatarShape: String, CaseIterable, Codable, Identifiable {
    case circle
    case roundedSquare

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .circle:        return "עיגול"
        case .roundedSquare: return "מרובע"
        }
    }

    /// A type-erased clip shape sized relative to the avatar dimension.
    func clipShape(for size: CGFloat) -> AnyShape {
        switch self {
        case .circle:
            return AnyShape(Circle())
        case .roundedSquare:
            return AnyShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        }
    }
}
