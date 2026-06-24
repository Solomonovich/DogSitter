import SwiftUI
import MapKit
import FirebaseFirestore
import Combine

class WalkViewModel: ObservableObject {
    @Published var walk: Walk?
    private var listener: ListenerRegistration?
    
    func startListening(walkId: String, db: Firestore) {
        listener = db.collection("walks").document(walkId).addSnapshotListener { snapshot, error in
            guard let doc = snapshot else { return }
            self.walk = try? doc.data(as: Walk.self)
        }
    }
    
    func stopListening() {
        listener?.remove()
    }
    
    deinit {
        stopListening()
    }
}

struct WalkFullView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) private var theme

    let walkId: String
    let chatId: String
    let isSitter: Bool

    @StateObject private var viewModel = WalkViewModel()
    @ObservedObject private var tracker = LocationTracker.shared

    @State private var totalHoursToday: String = "00:00"

    // Image Upload
    @State private var showingImagePicker = false
    @State private var selectedLightboxURL: String? = nil

    // Computed duration based on the shared tracker or the static completed walk duration
    var activeDuration: Double {
        if viewModel.walk?.status == "active" {
            return Double(tracker.elapsedSeconds) / 60.0
        } else {
            return viewModel.walk?.duration ?? 0.0
        }
    }

    // Recap shown after stopping; a nudge token to recenter the owner's map; a transient
    // in-app alert for the owner (out-of-app owner alerts would need push, which is out of scope).
    @State private var recapWalk: Walk?
    @State private var recenterToken: Int = 0
    @State private var ownerAlert: String?

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            theme.color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Map Area
                GeometryReader { geo in
                    ZStack(alignment: .bottomTrailing) {
                        WalkMapView(walk: viewModel.walk, tracker: tracker, region: $region, accentColor: theme.color.accent, isSitter: isSitter, recenterToken: recenterToken)
                            .frame(height: geo.size.height)

                        if isSitter && viewModel.walk?.status == "active" {
                            Button(action: { showingImagePicker = true }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(theme.color.accent)
                                    .frame(width: 48, height: 48)
                                    .background(theme.color.surface)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                            }
                            .accessibilityLabel("צלם תמונה")
                            .padding()
                        } else if !isSitter && viewModel.walk?.status == "active" {
                            Button(action: { recenterToken += 1 }) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(theme.color.accent)
                                    .frame(width: 48, height: 48)
                                    .background(theme.color.surface)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                            }
                            .accessibilityLabel("מרכז על המיקום הנוכחי")
                            .padding()
                        }
                    }
                }
                .frame(height: UIScreen.main.bounds.height * 0.6)
                
                // Info Area
                ScrollView {
                    VStack(spacing: 8) {
                        // Time Bubble
                        InfoBubble {
                            HStack {
                                if viewModel.walk?.status == "active" {
                                    if isWalkPaused {
                                        Text("מושהה")
                                            .bold()
                                            .foregroundStyle(.orange)
                                    } else {
                                        Text("פעיל")
                                            .bold()
                                            .foregroundStyle(theme.color.success)
                                    }
                                } else {
                                    let startTimeStr = viewModel.walk?.startTime.dateValue().formatted(date: .omitted, time: .shortened) ?? ""
                                    let endTimeStr = viewModel.walk?.endTime?.dateValue().formatted(date: .omitted, time: .shortened) ?? ""
                                    Text("\(startTimeStr) - \(endTimeStr)")
                                        .foregroundStyle(theme.color.textSecondary)
                                }

                                Spacer()

                                Text("זמן - \(formatElapsedTime(Int(activeDuration * 60)))")
                                    .bold()
                                    .foregroundStyle(theme.color.accent)
                            }
                        }

                        // Distance Bubble
                        InfoBubble {
                            HStack {
                                Text("\(String(format: "%.2f", viewModel.walk?.status == "active" ? tracker.totalDistance : (viewModel.walk?.distance ?? 0.0))) ק״מ")

                                Spacer()

                                Text("מרחק הליכה")
                                    .bold()
                                    .foregroundStyle(theme.color.accent)
                            }
                        }

                        // Photos Bubble
                        InfoBubble {
                            VStack {
                                Text("תמונות")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(theme.color.accent)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack {
                                        if let photos = viewModel.walk?.photoURLs, !photos.isEmpty {
                                            ForEach(photos, id: \.self) { urlString in
                                                CachedAsyncImage(urlString, contentMode: .fill, targetSize: 160) {
                                                    theme.color.surfaceSecondary
                                                }
                                                .frame(width: 80, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.md))
                                                .onTapGesture {
                                                    selectedLightboxURL = urlString
                                                }
                                            }
                                        } else {
                                            Text("אין תמונות עדיין")
                                                .foregroundStyle(theme.color.textSecondary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                        }
                                    }
                                }
                                .frame(height: 80)
                            }
                        }
                        .frame(minHeight: 130)

                        if isSitter && viewModel.walk?.status == "active" {
                            HStack(spacing: 12) {
                                Button(action: togglePause) {
                                    Label(tracker.isPaused ? "המשך" : "השהה",
                                          systemImage: tracker.isPaused ? "play.fill" : "pause.fill")
                                        .bold()
                                        .foregroundStyle(theme.color.textOnAccent)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(tracker.isPaused ? theme.color.success : theme.color.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                                }

                                Button(action: stopWalk) {
                                    Text("עצור הליכה")
                                        .bold()
                                        .foregroundStyle(theme.color.textOnAccent)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(theme.color.error)
                                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.color.surface)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .ignoresSafeArea(edges: .bottom)
            }
            
            // Top Bubble
            VStack {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(theme.color.textPrimary)
                            .padding(12)
                            .background(theme.color.surface)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 4)
                    }
                    .accessibilityLabel("חזור")
                    .padding(.leading, 16)

                    Spacer()
                }
                .padding(.top, 16)

                HStack {
                    Text("סך שעות הליכה היום")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(theme.color.textPrimary)

                    Spacer()

                    Text(totalHoursToday)
                        .font(.headline)
                        .foregroundStyle(theme.color.accent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(theme.color.surface)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                
                Spacer()
            }
            
            // Lightbox
            if let urlString = selectedLightboxURL {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea().onTapGesture { selectedLightboxURL = nil }
                    CachedAsyncImage(urlString, contentMode: .fit, targetSize: 1000) {
                        LottieProgressView(size: 40)
                    }
                    .padding()
                    VStack {
                        HStack {
                            Button(action: { selectedLightboxURL = nil }) {
                                Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.white).padding()
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .zIndex(999)
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .swipeToGoBack { presentationMode.wrappedValue.dismiss() }
        .overlay(alignment: .top) {
            if let ownerAlert {
                Text(ownerAlert)
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .padding(.top, 70)
                    .onTapGesture { self.ownerAlert = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: ownerAlert)
        .onAppear {
            viewModel.startListening(walkId: walkId, db: appState.db)
            Task {
                totalHoursToday = await appState.getTotalWalkHoursForChat(chatId: chatId)

                // Sync from Firestore, then (sitter) re-wire the background driver + Live
                // Activity and re-attach GPS. The 5s sync now lives in LocationTracker, so
                // it keeps running once attached even if this screen is dismissed.
                if let doc = try? await appState.db.collection("walks").document(walkId).getDocument(as: Walk.self) {
                    let firestoreCoordinates = doc.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

                    await MainActor.run {
                        if firestoreCoordinates.count > tracker.coordinates.count {
                            // Reconstruct paused-adjusted elapsed from the last synced duration.
                            tracker.restoreRoute(firestoreCoordinates,
                                                 distanceKm: doc.distance,
                                                 elapsedSeconds: Int(doc.duration * 60))
                        }

                        if isSitter && doc.status == "active" {
                            appState.beginWalkSession(walkId: walkId,
                                                      dogName: appState.dogName(forPostId: doc.postId),
                                                      isSitter: true)
                            tracker.reattachTracking()
                            if doc.isPaused == true { tracker.pauseWalk() }
                        }
                    }
                }
            }
        }
        .onChange(of: viewModel.walk?.coordinates) { _ in evaluateOwnerAlerts() }
        .sheet(isPresented: $showingImagePicker) {
            ChatImagePicker(sourceType: .camera) { image in
                Task { await uploadPhoto(image) }
            }
        }
        .sheet(item: $recapWalk, onDismiss: { presentationMode.wrappedValue.dismiss() }) { w in
            WalkRecapView(walk: w)
        }
    }

    private var isWalkPaused: Bool {
        (viewModel.walk?.isPaused ?? false) || tracker.isPaused
    }

    private func togglePause() {
        if tracker.isPaused {
            tracker.resumeWalk()
            Task { await appState.setWalkPaused(walkId: walkId, isPaused: false) }
        } else {
            tracker.pauseWalk()
            Task { await appState.setWalkPaused(walkId: walkId, isPaused: true) }
        }
    }

    /// Owner-only in-app alerts (the app must be open). Out-of-app owner alerts would
    /// require remote push, which is intentionally out of scope.
    private func evaluateOwnerAlerts() {
        guard !isSitter, let walk = viewModel.walk, walk.status == "active" else { return }
        let coords = walk.coordinates
        if let first = coords.first, let last = coords.last {
            let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
            let current = CLLocation(latitude: last.latitude, longitude: last.longitude)
            if current.distance(from: start) > 1500 {
                ownerAlert = "המטפל התרחק מנקודת ההתחלה"
                return
            }
        }
        if walk.duration > 120 {
            ownerAlert = "ההליכה נמשכת זמן רב מהרגיל"
        }
    }
    
    private func uploadPhoto(_ image: UIImage) async {
        let photoId = UUID().uuidString
        let path = "dogsitter/walks/\(walkId)"
        do {
            let url = try await CloudinaryHelper.uploadPhoto(image: image, userId: appState.currentUser?.id ?? "unknown", petId: path, index: photoId.hashValue)
            await appState.addWalkPhoto(walkId: walkId, imageURL: url)
        } catch {
            print("Failed to upload walk photo: \(error)")
        }
    }
    
    private func stopWalk() {
        let finalDistance = tracker.totalDistance
        let finalDuration = activeDuration
        let routeCoords = tracker.coordinates
        tracker.stopTracking()
        appState.endWalkSession() // ends the Live Activity + clears the driver

        guard var completed = viewModel.walk else {
            presentationMode.wrappedValue.dismiss()
            return
        }
        let msgId = completed.messageId
        Task {
            await appState.stopWalk(walkId: walkId, messageId: msgId, chatId: chatId, finalDistance: finalDistance, finalDuration: finalDuration)
            await MainActor.run {
                // Build a completed snapshot for the recap (the live doc updates async).
                completed.status = "completed"
                completed.distance = finalDistance
                completed.duration = finalDuration
                if !routeCoords.isEmpty {
                    completed.coordinates = routeCoords.map { WalkCoordinate(latitude: $0.latitude, longitude: $0.longitude, timestamp: Timestamp()) }
                }
                recapWalk = completed
            }
        }
    }
    
    private func formatElapsedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct InfoBubble<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    @Environment(\.theme) private var theme
    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.color.accent.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
    }
}

// Wrapper for MapKit Polyline
struct WalkMapView: UIViewRepresentable {
    var walk: Walk?
    @ObservedObject var tracker: LocationTracker
    @Binding var region: MKCoordinateRegion
    var accentColor: Color = Color(hex: "#4A90D9")
    var isSitter: Bool = false
    /// Bumping this from the owner's recenter button forces a re-fit of the map.
    var recenterToken: Int = 0

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        _ = recenterToken // referenced so a recenter tap re-runs this and re-fits.
        let walkStatus = walk?.status ?? "active"
        // Only the tracking (sitter) device shows the blue user-location dot.
        mapView.showsUserLocation = isSitter && walkStatus == "active"

        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        // Sitter draws the live segmented route (a gap per pause); everyone else (owner /
        // completed walk) draws the persisted flat route as one polyline.
        var segments: [[CLLocationCoordinate2D]] = []
        if isSitter && walkStatus == "active" && !tracker.routeSegments.isEmpty {
            segments = tracker.routeSegments
        } else if let walkCoords = walk?.coordinates {
            segments = [walkCoords.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }]
        }

        for seg in segments where seg.count > 1 {
            mapView.addOverlay(MKPolyline(coordinates: seg, count: seg.count))
        }

        let allCoords = segments.flatMap { $0 }

        // Owner: a live marker at the sitter's latest reported position.
        if !isSitter && walkStatus == "active", let last = allCoords.last {
            let ann = MKPointAnnotation()
            ann.coordinate = last
            ann.title = "מיקום נוכחי"
            mapView.addAnnotation(ann)
        }

        updateMapRegion(mapView, coordinates: allCoords)
    }
    
    func updateMapRegion(_ mapView: MKMapView, coordinates: [CLLocationCoordinate2D]) {
        if coordinates.count <= 1 {
            if let location = coordinates.first ?? LocationTracker.shared.currentLocation?.coordinate {
                let region = MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)
                )
                mapView.setRegion(region, animated: true)
            }
            return
        }
        
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        var rect = polyline.boundingMapRect
        
        rect = rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2)
        
        let region = MKCoordinateRegion(rect)
        let finalRegion = MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: max(region.span.latitudeDelta, 0.009),
                longitudeDelta: max(region.span.longitudeDelta, 0.009)
            )
        )
        
        mapView.setRegion(finalRegion, animated: true)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: WalkMapView
        init(_ parent: WalkMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(parent.accentColor)
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
