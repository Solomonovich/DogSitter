import SwiftUI
import UIKit

/// Corner-radius scale. The base values can be uniformly scaled to support the
/// user's roundness preference (`CornerStyle`); `pill` always stays fully round.
struct Radius: Equatable {
    var xs:     CGFloat
    var sm:     CGFloat
    var md:     CGFloat
    var card:   CGFloat
    var lg:     CGFloat
    var xl:     CGFloat
    var sheet:  CGFloat
    var button: CGFloat
    var pill:   CGFloat = 999

    init(scale: CGFloat = 1.0) {
        xs     = 6  * scale
        sm     = 10 * scale
        md     = 14 * scale
        card   = 16 * scale
        lg     = 20 * scale
        xl     = 24 * scale
        sheet  = 28 * scale
        button = 25 * scale
        pill   = 999
    }

    static let standard = Radius()

    // Roundness presets (used by CornerStyle).
    static let rounded = Radius(scale: 1.0)
    static let soft    = Radius(scale: 0.6)
    static let sharp   = Radius(scale: 0.15)
}

// MARK: - Selective corner rounding (moved from BrowsePostsView)

extension View {
    /// Rounds only the specified corners. Uses physical UIRectCorner (direction-independent).
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
