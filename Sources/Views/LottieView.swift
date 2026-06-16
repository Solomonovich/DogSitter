import SwiftUI
import Lottie

/// A SwiftUI wrapper around Lottie's LottieAnimationView.
struct LottieView: UIViewRepresentable {
    var name: String
    var loopMode: LottieLoopMode = .loop
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var animationSpeed: CGFloat = 1.0

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let animationView = LottieAnimationView(name: name, bundle: .main)
        animationView.loopMode = loopMode
        animationView.contentMode = contentMode
        animationView.animationSpeed = animationSpeed
        animationView.play()
        
        animationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.heightAnchor.constraint(equalTo: view.heightAnchor),
            animationView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])
        
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let animationView = uiView.subviews.first(where: { $0 is LottieAnimationView }) as? LottieAnimationView {
            animationView.animationSpeed = animationSpeed
        }
    }
}

/// A drop-in replacement for ProgressView() that uses your custom Lottie animation.
struct LottieProgressView: View {
    var size: CGFloat = 80

    var body: some View {
        LottieView(name: "icon")
            .scaleEffect(1.5) // Reduced scale so it doesn't clip or look too huge
            .frame(width: size, height: size)
            .clipped()
    }
}
