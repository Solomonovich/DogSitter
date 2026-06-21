import ActivityKit
import WidgetKit
import SwiftUI

// The extension does not inherit the app's design system or its global RTL/locale
// environment, so brand color + layout direction are set explicitly here.
private let brandAccent = Color(red: 0.29, green: 0.565, blue: 0.851) // ≈ #4A90D9

struct WalkActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            WalkLockScreenView(context: context)
                .environment(\.layoutDirection, .rightToLeft)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.dogName).font(.caption).bold()
                    } icon: {
                        Image(systemName: "pawprint.fill").foregroundStyle(brandAccent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WalkClockText(state: context.state)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(brandAccent)
                        .frame(maxWidth: 96)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "figure.walk")
                        Text(distanceText(context.state.distanceKm))
                        if context.state.isPaused {
                            Spacer()
                            Label("מושהה", systemImage: "pause.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "pawprint.fill")
                    .foregroundStyle(brandAccent)
            } compactTrailing: {
                WalkClockText(state: context.state)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(brandAccent)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "pawprint.fill")
                    .foregroundStyle(brandAccent)
            }
            .widgetURL(URL(string: "dogsitter://walk/\(context.attributes.walkId)"))
        }
    }
}

/// Auto-ticking clock on the device (no per-second Activity pushes) while running;
/// a frozen snapshot string while paused.
struct WalkClockText: View {
    let state: WalkActivityAttributes.ContentState
    var body: some View {
        if state.isPaused {
            Text(timeString(state.frozenElapsedSeconds))
                .monospacedDigit()
        } else {
            Text(timerInterval: state.logicalStart...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        }
    }
}

struct WalkLockScreenView: View {
    let context: ActivityViewContext<WalkActivityAttributes>
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(brandAccent.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "pawprint.fill").foregroundStyle(brandAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.dogName).font(.headline)
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk").font(.caption2)
                    Text(distanceText(context.state.distanceKm)).font(.subheadline)
                    if context.state.isPaused {
                        Text("· מושהה").font(.caption).foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            WalkClockText(state: context.state)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(brandAccent)
        }
        .padding()
    }
}

private func distanceText(_ km: Double) -> String {
    String(format: "%.2f ק\"מ", km)
}

private func timeString(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
