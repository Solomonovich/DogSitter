import SwiftUI
import UIKit

/// Corner-radius scale.
struct Radius: Equatable {
    let xs:     CGFloat = 6
    let sm:     CGFloat = 10
    let md:     CGFloat = 14
    let card:   CGFloat = 16
    let lg:     CGFloat = 20
    let xl:     CGFloat = 24
    let sheet:  CGFloat = 28
    let button: CGFloat = 25
    let pill:   CGFloat = 999

    static let standard = Radius()
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
