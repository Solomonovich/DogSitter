import SwiftUI

/// Dimmed overlay with the app's Lottie spinner. Replaces repeated
/// `Color.black.opacity(0.3) + LottieProgressView` blocks.
struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    var size: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    LottieProgressView(size: size)
                }
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func loadingOverlay(_ isLoading: Bool, size: CGFloat = 90) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, size: size))
    }
}
