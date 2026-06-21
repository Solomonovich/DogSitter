import Foundation
import ActivityKit

/// Shared between the app target and the WalkActivityWidget extension. Keep this file
/// dependency-free (only Foundation + ActivityKit) — it is compiled into BOTH targets.
struct WalkActivityAttributes: ActivityAttributes {
    /// The live, changing part of the walk shown in the Dynamic Island / Lock Screen.
    public struct ContentState: Codable, Hashable {
        var distanceKm: Double
        var isPaused: Bool
        /// Wall-clock instant the running timer should count up from. Equals the walk's
        /// real start pushed forward by any accumulated paused time, so the on-device
        /// `Text(timerInterval:)` clock shows paused-adjusted elapsed without per-second
        /// pushes. When paused, the UI renders `frozenElapsedSeconds` statically instead.
        var logicalStart: Date
        /// Paused-adjusted elapsed seconds captured at the last update — used to render a
        /// frozen clock while `isPaused` is true.
        var frozenElapsedSeconds: Int
    }

    /// Fixed for the life of the walk.
    var dogName: String
    var walkId: String
    var startTime: Date
}
