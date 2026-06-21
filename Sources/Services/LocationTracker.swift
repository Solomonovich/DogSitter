import Foundation
import CoreLocation
import Combine
import MapKit

// F-24: keep diagnostic logging out of release builds (device/console logs can be
// harvested). Sensitive values (coordinates, addresses) are never logged.
private func dbg(_ message: @autoclosure () -> String) {
#if DEBUG
    print(message())
#endif
}

class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()

    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    /// Route broken into segments so a pause renders as a visible gap on the map
    /// (one polyline per segment). Persisted to Firestore as a flattened array.
    @Published var routeSegments: [[CLLocationCoordinate2D]] = []
    @Published var totalDistance: Double = 0.0 // kilometers
    @Published var isTracking: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentRegion: MKCoordinateRegion?
    /// Paused-adjusted active seconds — the 1s timer only ticks while not paused.
    @Published var elapsedSeconds: Int = 0

    /// Flattened view of the recorded route. Segment boundaries are a client-only
    /// visual concern, so Firestore/distance keep using this flat array.
    var coordinates: [CLLocationCoordinate2D] { routeSegments.flatMap { $0 } }

    private var timer: Timer?       // 1s elapsed clock
    private var syncTimer: Timer?   // 5s authoritative driver (Firestore + Live Activity)

    // Hooks wired by the walk-start flow so the tracker can drive the sync + Live
    // Activity without importing AppState. Only the sitter writes (gated by isSitter).
    var onSync: ((_ coordinates: [CLLocationCoordinate2D], _ distanceKm: Double, _ durationMin: Double) -> Void)?
    var onLiveActivityUpdate: ((_ distanceKm: Double, _ isPaused: Bool, _ elapsedSeconds: Int) -> Void)?
    var isSitter: Bool = false

    private let strayThresholdMeters: CLLocationDistance = 1500
    private let longWalkSeconds: Int = 7200 // 2 hours

    private override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // meters
        manager.activityType = .fitness
        // allowsBackgroundLocationUpdates is enabled only while a walk is active
        // (see configureBackgroundUpdates). Setting it true requires UIBackgroundModes:
        // [location] in Info.plist or CoreLocation crashes.
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        manager.requestWhenInUseAuthorization()
        routeSegments = [[]]
        totalDistance = 0.0
        elapsedSeconds = 0
        isTracking = true
        isPaused = false
        configureBackgroundUpdates(true)
        manager.startUpdatingLocation()
        startElapsedTimer()
        startSyncTimer()
        dbg("Started Location Tracking")
    }

    func stopTracking() {
        timer?.invalidate(); timer = nil
        syncTimer?.invalidate(); syncTimer = nil
        isTracking = false
        isPaused = false
        manager.stopUpdatingLocation()
        configureBackgroundUpdates(false)
        dbg("Stopped Location Tracking")
    }

    /// Re-attach to an in-flight walk after returning to the walk screen / app relaunch
    /// (formerly `resumeTracking`). Does NOT reset the recorded route.
    func reattachTracking() {
        if !isTracking {
            manager.requestWhenInUseAuthorization()
            isTracking = true
            configureBackgroundUpdates(true)
            manager.startUpdatingLocation()
            startElapsedTimer()
            startSyncTimer()
            dbg("Re-attached Location Tracking")
        }
    }

    /// Pause: freeze elapsed time + distance accumulation, keep the walk active.
    func pauseWalk() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        timer?.invalidate(); timer = nil // freeze the clock
        emitLiveActivityUpdate()
        dbg("Paused walk")
    }

    /// Resume after a pause: start a new route segment so the map doesn't draw a
    /// straight line across the gap, and restart the clock.
    func resumeWalk() {
        guard isTracking, isPaused else { return }
        isPaused = false
        routeSegments.append([]) // new segment after the paused gap
        startElapsedTimer()
        emitLiveActivityUpdate()
        dbg("Resumed walk")
    }

    func resetTracking() {
        stopTracking()
        routeSegments = []
        totalDistance = 0.0
        elapsedSeconds = 0
        isPaused = false
        onSync = nil
        onLiveActivityUpdate = nil
        isSitter = false
    }

    /// Restore a route from Firestore on re-attach without counting it as new distance.
    func restoreRoute(_ coords: [CLLocationCoordinate2D], distanceKm: Double, elapsedSeconds: Int) {
        routeSegments = coords.isEmpty ? [[]] : [coords]
        totalDistance = distanceKm
        self.elapsedSeconds = max(0, elapsedSeconds)
    }

    // MARK: - Private helpers

    private func configureBackgroundUpdates(_ enabled: Bool) {
        manager.allowsBackgroundLocationUpdates = enabled
        manager.pausesLocationUpdatesAutomatically = false
        if enabled { manager.showsBackgroundLocationIndicator = true }
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.isTracking, !self.isPaused else { return }
                self.elapsedSeconds += 1
            }
        }
    }

    private func startSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.isTracking, !self.isPaused else { return }
                if self.isSitter {
                    self.onSync?(self.coordinates, self.totalDistance, Double(self.elapsedSeconds) / 60.0)
                    self.checkSitterAlerts()
                }
                self.emitLiveActivityUpdate()
            }
        }
    }

    private func emitLiveActivityUpdate() {
        onLiveActivityUpdate?(totalDistance, isPaused, elapsedSeconds)
    }

    /// Local notifications on the tracking (sitter) device — fire once each per session.
    /// These run in the background because background location keeps the app alive.
    private func checkSitterAlerts() {
        guard let first = coordinates.first, let last = coordinates.last else { return }
        let start = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let current = CLLocation(latitude: last.latitude, longitude: last.longitude)
        if current.distance(from: start) > strayThresholdMeters {
            NotificationManager.shared.scheduleLocalAlert(
                title: "התרחקת מנקודת ההתחלה",
                body: "אתה רחוק מהמקום שבו התחילה ההליכה.",
                identifier: "walk-stray")
        }
        if elapsedSeconds > longWalkSeconds {
            NotificationManager.shared.scheduleLocalAlert(
                title: "הליכה ארוכה",
                body: "ההליכה נמשכת כבר זמן רב — שכחת לסיים?",
                identifier: "walk-long")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter inaccurate / stale fixes (also tames simulation jumps).
        if location.horizontalAccuracy > 65 { return }
        if location.timestamp.timeIntervalSinceNow < -5.0 { return }

        DispatchQueue.main.async {
            self.currentLocation = location
            if self.coordinates.isEmpty || !self.isTracking {
                // Center map on first location update.
                self.currentRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)
                )
            }

            guard self.isTracking, !self.isPaused else { return }
            if self.routeSegments.isEmpty { self.routeSegments = [[]] }

            let newCoord = location.coordinate
            let currentSegmentEmpty = self.routeSegments.last?.isEmpty ?? true

            if let lastCoord = self.coordinates.last {
                let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                let distanceMeters = location.distance(from: lastLoc)
                if distanceMeters > 1 {
                    // Only count distance when continuing the current segment — never
                    // across a paused gap (current segment still empty after a resume).
                    if !currentSegmentEmpty {
                        self.totalDistance += distanceMeters / 1000.0
                    }
                    self.routeSegments[self.routeSegments.count - 1].append(newCoord)
                }
            } else {
                self.routeSegments[self.routeSegments.count - 1].append(newCoord)
            }
        }
    }
}
