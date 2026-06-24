import SwiftUI
import UIKit

/// Restores a "swipe from the left screen edge to go back" gesture on screens
/// that lost the system one.
///
/// Why this exists: a few screens hide the navigation bar or use a custom back
/// button (`ChatDetailView`, `PreWalkView`, `WalkFullView`), which disables
/// UIKit's built-in interactive-pop swipe — and `.fullScreenCover` never had a
/// back-swipe to begin with. This re-adds a single, consistent left-edge back
/// gesture that simply invokes the same dismiss the back button already uses, so
/// it works for both navigation pushes and modal covers.
///
/// Built on `UIScreenEdgePanGestureRecognizer` with the *physical* `.left` edge
/// (intentionally not RTL-mirrored, per the requested "swipe from the left").
/// Because it only begins inside the system edge zone, it never competes with
/// in-content scroll views, the drag-to-dismiss sheets, the map pan, or the
/// calendar drag elsewhere in the app.
private struct EdgeSwipeBack: UIViewControllerRepresentable {
    let onBack: () -> Void

    func makeUIViewController(context: Context) -> EdgeSwipeBackController {
        let controller = EdgeSwipeBackController()
        controller.onBack = onBack
        return controller
    }

    func updateUIViewController(_ controller: EdgeSwipeBackController, context: Context) {
        controller.onBack = onBack
    }
}

final class EdgeSwipeBackController: UIViewController, UIGestureRecognizerDelegate {
    var onBack: (() -> Void)?
    private weak var hostView: UIView?
    private weak var recognizer: UIScreenEdgePanGestureRecognizer?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachRecognizerIfNeeded()
    }

    /// Attach the recognizer to the enclosing screen's view (this representable's
    /// SwiftUI host controller) rather than our own zero-size view, so the
    /// gesture covers the whole screen. Because it lives on the host controller's
    /// view, UIKit tears it down automatically when the screen is popped/dismissed.
    private func attachRecognizerIfNeeded() {
        guard recognizer == nil, let target = parent?.view ?? view.superview else { return }
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        edge.edges = .left            // physical left edge, regardless of layout direction
        edge.delegate = self
        target.addGestureRecognizer(edge)
        hostView = target
        recognizer = edge
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended, let view = gesture.view else { return }
        let translationX = gesture.translation(in: view).x
        let velocityX = gesture.velocity(in: view).x
        // Commit "back" only on a deliberate left→right swipe (distance or a flick).
        if translationX > 60 || velocityX > 300 {
            onBack?()
        }
    }

    /// The swipe begins only in the edge zone, so let it coexist with whatever
    /// recognizer (e.g. a scroll view's pan) also wants the touch. This guarantees
    /// the edge swipe still fires even when started over scrollable content.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    deinit {
        if let recognizer, let hostView {
            hostView.removeGestureRecognizer(recognizer)
        }
    }
}

extension View {
    /// Adds a left-edge "swipe right to go back" gesture that runs `onBack`
    /// (which should pop or dismiss the screen).
    ///
    /// Apply ONLY to screens whose hidden/custom back button or modal
    /// presentation disabled the system interactive-pop gesture. Screens that
    /// keep the default navigation back button already have a native back-swipe;
    /// adding this there would dismiss twice.
    func swipeToGoBack(_ onBack: @escaping () -> Void) -> some View {
        background(EdgeSwipeBack(onBack: onBack).frame(width: 0, height: 0))
    }
}
