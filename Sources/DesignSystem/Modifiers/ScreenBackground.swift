import SwiftUI

/// Applies the themed screen background behind the content.
/// Honors the user's `backgroundStyle` preference (solid fill vs. soft brand gradient).
struct ScreenBackgroundModifier: ViewModifier {
    @Environment(\.theme) private var theme
    var edges: Edge.Set
    func body(content: Content) -> some View {
        content.background(backdrop)
    }

    @ViewBuilder private var backdrop: some View {
        switch theme.backgroundStyle {
        case .gradient:
            BrandGradient()
        case .solid:
            theme.color.background.ignoresSafeArea(edges: edges)
        }
    }
}

extension View {
    func screenBackground(_ edges: Edge.Set = .all) -> some View {
        modifier(ScreenBackgroundModifier(edges: edges))
    }
}

/// Soft brand gradient backdrop used on auth / onboarding screens.
struct BrandGradient: View {
    @Environment(\.theme) private var theme
    var body: some View {
        ZStack {
            theme.color.background
            LinearGradient(
                colors: theme.color.accentGradient.map { $0.opacity(0.10) },
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
