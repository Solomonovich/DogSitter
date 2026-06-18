import SwiftUI

/// A single named shadow definition.
struct AppShadow: Equatable {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

/// Elevation scale — named shadow tiers replacing ad-hoc `.shadow(...)` calls.
struct Elevation: Equatable {
    let none   = AppShadow(color: .clear,                radius: 0,  x: 0, y: 0)
    let card   = AppShadow(color: .black.opacity(0.08),  radius: 10, x: 0, y: 5)
    let raised = AppShadow(color: .black.opacity(0.12),  radius: 8,  x: 0, y: 4)
    let float  = AppShadow(color: .black.opacity(0.15),  radius: 12, x: 0, y: 6)

    static let standard = Elevation()
}

extension View {
    /// Applies a named elevation shadow.
    func elevation(_ shadow: AppShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
