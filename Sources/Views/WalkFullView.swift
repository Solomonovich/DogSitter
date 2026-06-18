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

    // Upload Timer — held in @State so it isn't recreated on every body evaluation.
    @State private var uploadTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
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
                        WalkMapView(walk: viewModel.walk, tracker: tracker, region: $region, accentColor: theme.color.accent)
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
                                    Text("פעיל")
                                        .bold()
                                        .foregroundStyle(theme.color.success)
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

                        if viewModel.walk?.status == "active" {
                            Button(action: stopWalk) {
                                Text("עצור הליכה")
                                    .bold()
                                    .foregroundStyle(theme.color.textOnAccent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(theme.color.error)
                                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
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
        .onAppear {
            viewModel.startListening(walkId: walkId, db: appState.db)
            Task { 
                totalHoursToday = await appState.getTotalWalkHoursForChat(chatId: chatId) 
                
                // Firestore Syncing logic
                if let doc = try? await appState.db.collection("walks").document(walkId).getDocument(as: Walk.self) {
                    let firestoreCoordinates = doc.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    
                    // Run state updates on main thread
                    await MainActor.run {
                        if firestoreCoordinates.count > tracker.coordinates.count {
                            tracker.coordinates = firestoreCoordinates
                            tracker.totalDistance = doc.distance
                            
                            // Synchronize elapsed time with the actual start time
                            let elapsed = Date().timeIntervalSince(doc.startTime.dateValue())
                            tracker.elapsedSeconds = Int(elapsed)
                        }
                        
                        if isSitter && doc.status == "active" {
                            tracker.resumeTracking()
                        }
                    }
                }
            }
        }
        .onReceive(uploadTimer) { _ in
            if isSitter && viewModel.walk?.status == "active" {
                Task {
                    await appState.updateWalkCoordinates(walkId: walkId, coordinates: tracker.coordinates, distance: tracker.totalDistance, duration: activeDuration)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ChatImagePicker(sourceType: .camera) { image in
                Task { await uploadPhoto(image) }
            }
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
        tracker.stopTracking()
        if let msgId = viewModel.walk?.messageId {
            Task {
                await appState.stopWalk(walkId: walkId, messageId: msgId, chatId: chatId, finalDistance: tracker.totalDistance, finalDuration: activeDuration)
                // Dismiss the full-screen view to go back to chat
                presentationMode.wrappedValue.dismiss()
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

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        return map
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        let walkStatus = walk?.status ?? "active"
        mapView.showsUserLocation = (walkStatus == "active")
        
        mapView.removeOverlays(mapView.overlays)
        
        var coords: [CLLocationCoordinate2D] = []
        if walkStatus == "active" && !tracker.coordinates.isEmpty {
            coords = tracker.coordinates
        } else if let walkCoords = walk?.coordinates {
            coords = walkCoords.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        
        if coords.count > 1 {
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            mapView.addOverlay(polyline)
        }
        
        updateMapRegion(mapView, coordinates: coords)
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
