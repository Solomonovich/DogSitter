import Foundation
import ActivityKit

/// Owns the lifecycle of the walk Live Activity (Dynamic Island + Lock Screen).
/// Updates are local — driven by `LocationTracker`'s sync loop while the app is alive
/// (background location keeps it alive during a walk). No APNs / server involved.
final class WalkLiveActivityManager {
    static let shared = WalkLiveActivityManager()
    private init() {}

    private var activity: Activity<WalkActivityAttributes>?

    func start(dogName: String, walkId: String, startTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity != nil { return }
        // Re-use an Activity left over from a previous launch for the same walk.
        if let existing = Activity<WalkActivityAttributes>.activities.first(where: { $0.attributes.walkId == walkId }) {
            activity = existing
            return
        }
        let attributes = WalkActivityAttributes(dogName: dogName, walkId: walkId, startTime: startTime)
        let state = WalkActivityAttributes.ContentState(
            distanceKm: 0,
            isPaused: false,
            logicalStart: startTime,
            frozenElapsedSeconds: 0
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            #if DEBUG
            print("Live Activity start failed: \(error)")
            #endif
        }
    }

    func update(distanceKm: Double, isPaused: Bool, elapsedSeconds: Int) {
        guard let activity = activity else { return }
        // logicalStart = now - elapsed, so the on-device Text(timerInterval:) shows the
        // paused-adjusted elapsed and stays stable while running.
        let logicalStart = Date().addingTimeInterval(-Double(elapsedSeconds))
        let state = WalkActivityAttributes.ContentState(
            distanceKm: distanceKm,
            isPaused: isPaused,
            logicalStart: logicalStart,
            frozenElapsedSeconds: elapsedSeconds
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        let current = activity
        activity = nil
        Task {
            if let current = current {
                await current.end(nil, dismissalPolicy: .immediate)
            }
            // Clean up any strays (e.g. left over from a crash).
            for a in Activity<WalkActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// On app launch, re-acquire an in-flight Activity so updates/end work after relaunch.
    func reattach() {
        guard activity == nil else { return }
        activity = Activity<WalkActivityAttributes>.activities.first
    }
}
