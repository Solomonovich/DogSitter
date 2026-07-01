import UIKit

/// Lightweight tactile-feedback helper — the app's first haptics layer.
/// Kept generic and static so any screen can adopt it. Each call prepares its
/// generator so the Taptic Engine fires without the first-tap latency; on devices
/// without a Taptic Engine these are safe no-ops.
enum Haptics {
    /// A physical tap — used for button presses / confirmations.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// A light "tick" — used when a selection changes (e.g. the role toggle).
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    /// A success / warning / error notification pattern.
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    static func error() { notify(.error) }
    static func success() { notify(.success) }
}
