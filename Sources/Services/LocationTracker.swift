import Foundation
import CoreLocation
import Combine
import MapKit

class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()
    
    private let manager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var coordinates: [CLLocationCoordinate2D] = []
    @Published var totalDistance: Double = 0.0 // kilometers
    @Published var isTracking: Bool = false
    @Published var currentRegion: MKCoordinateRegion?
    @Published var elapsedSeconds: Int = 0
    
    private var timer: Timer?
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // meters
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = false
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        manager.requestWhenInUseAuthorization()
        coordinates.removeAll()
        totalDistance = 0.0
        elapsedSeconds = 0
        isTracking = true
        manager.startUpdatingLocation()
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.elapsedSeconds += 1
            }
        }
        print("Started Location Tracking")
    }
    
    func stopTracking() {
        timer?.invalidate()
        timer = nil
        isTracking = false
        manager.stopUpdatingLocation()
        print("Stopped Location Tracking")
    }
    
    func resumeTracking() {
        if !isTracking {
            manager.requestWhenInUseAuthorization()
            isTracking = true
            manager.startUpdatingLocation()
            
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.elapsedSeconds += 1
                }
            }
            print("Resumed Location Tracking")
        }
    }
    
    func resetTracking() {
        stopTracking()
        coordinates = []
        totalDistance = 0.0
        elapsedSeconds = 0
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Mock filter to prevent crazy jumps during simulation
        if location.horizontalAccuracy > 65 { return }
        
        // Ignore old cached locations
        if location.timestamp.timeIntervalSinceNow < -5.0 { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
            if self.coordinates.isEmpty || !self.isTracking {
                // Center map on first location update
                let region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.009, longitudeDelta: 0.009)
                )
                self.currentRegion = region
            }
            
            guard self.isTracking else { return }
            
            let newCoord = location.coordinate
            
            if let lastCoord = self.coordinates.last {
                let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                let distanceMeters = location.distance(from: lastLoc)
                // Add distance only if movement is reasonable (ignore tiny shifts)
                if distanceMeters > 1 {
                    self.totalDistance += (distanceMeters / 1000.0) // Convert to km
                    self.coordinates.append(newCoord)
                }
            } else {
                self.coordinates.append(newCoord)
            }
        }
    }
}
