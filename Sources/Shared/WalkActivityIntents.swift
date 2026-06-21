import Foundation
import AppIntents

// Shared between the app target and the WalkActivityWidget extension. Keep this file
// dependency-free (only Foundation + AppIntents) — it compiles into BOTH targets, so it
// must NOT reference app-only types (LocationTracker, AppState, Firebase).

enum WalkActivityCommand {
    case togglePause(walkId: String)
    case end(walkId: String)
}

/// In-process bridge: a `LiveActivityIntent`'s `perform()` runs in the APP's process, so the
/// app sets `handler` once and the intents call through it. (Unused in the widget process.)
final class WalkActivityActionCenter {
    static let shared = WalkActivityActionCenter()
    private init() {}
    var handler: ((WalkActivityCommand) async -> Void)?
}

/// Pause/resume the active walk straight from the Live Activity.
struct ToggleWalkPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "השהה או המשך הליכה"

    @Parameter(title: "Walk ID")
    var walkId: String

    init() {}
    init(walkId: String) { self.walkId = walkId }

    func perform() async throws -> some IntentResult {
        await WalkActivityActionCenter.shared.handler?(.togglePause(walkId: walkId))
        return .result()
    }
}

/// End the active walk straight from the Live Activity.
struct EndWalkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "סיים הליכה"

    @Parameter(title: "Walk ID")
    var walkId: String

    init() {}
    init(walkId: String) { self.walkId = walkId }

    func perform() async throws -> some IntentResult {
        await WalkActivityActionCenter.shared.handler?(.end(walkId: walkId))
        return .result()
    }
}
