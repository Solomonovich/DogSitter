import SwiftUI
import MapKit
import CoreLocation

/// Post-walk summary shown when a walk is stopped: route snapshot, distance, duration,
/// average pace, and the walk's photos — with a share button.
struct WalkRecapView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let walk: Walk

    @State private var snapshot: UIImage?

    private var coords: [CLLocationCoordinate2D] {
        walk.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Average pace as mm:ss per km (guards against zero distance).
    private var paceText: String {
        guard walk.distance > 0.01 else { return "—" }
        let secPerKm = (walk.duration * 60.0) / walk.distance
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.spacing.md) {
                    routeImage
                    statsRow
                    if !walk.photoURLs.isEmpty { photoStrip }
                }
                .padding()
            }
            .background(theme.color.background.ignoresSafeArea())
            .navigationTitle("סיכום הליכה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("סגור") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let snapshot {
                        ShareLink(
                            item: Image(uiImage: snapshot),
                            preview: SharePreview("הליכה", image: Image(uiImage: snapshot))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear(perform: renderSnapshot)
        }
    }

    @ViewBuilder private var routeImage: some View {
        ZStack {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
            } else {
                theme.color.surfaceSecondary
                if coords.count > 1 {
                    LottieProgressView(size: 40)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "map").font(.system(size: 28)).foregroundStyle(theme.color.textSecondary)
                        Text("אין מסלול להצגה").font(.caption).foregroundStyle(theme.color.textSecondary)
                    }
                }
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
    }

    private var statsRow: some View {
        HStack(spacing: theme.spacing.sm) {
            stat(title: "מרחק", value: String(format: "%.2f", walk.distance), unit: "ק״מ")
            stat(title: "זמן", value: formatElapsed(Int(walk.duration * 60)), unit: "")
            stat(title: "קצב", value: paceText, unit: "/ק״מ")
        }
    }

    private func stat(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(theme.color.textSecondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(theme.color.accent)
            if !unit.isEmpty {
                Text(unit).font(.caption2).foregroundStyle(theme.color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.spacing.sm)
        .background(theme.color.surface)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
    }

    private var photoStrip: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("תמונות").font(.subheadline).bold().foregroundStyle(theme.color.accent)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(walk.photoURLs, id: \.self) { urlString in
                        CachedAsyncImage(urlString, contentMode: .fill, targetSize: 160) {
                            theme.color.surfaceSecondary
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md))
                    }
                }
            }
        }
    }

    private func renderSnapshot() {
        guard snapshot == nil else { return }
        RouteSnapshotter.makeRouteSnapshot(
            coordinates: coords,
            size: CGSize(width: 600, height: 360),
            strokeColor: UIColor(theme.color.accent)
        ) { image in
            self.snapshot = image
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
