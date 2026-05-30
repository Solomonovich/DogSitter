import Foundation
import CoreLocation
import Combine

class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var coordinates: [CLLocationCoordinate2D] = []
    @Published var totalDistance: Double = 0.0 // kilometers
    @Published var isTracking: Bool = false
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // meters
        manager.activityType = .fitness
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        coordinates.removeAll()
        totalDistance = 0.0
        isTracking = true
        manager.startUpdatingLocation()
        print("Started Location Tracking")
    }
    
    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
        print("Stopped Location Tracking")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Mock filter to prevent crazy jumps during simulation
        if location.horizontalAccuracy > 65 { return }
        
        // Ignore old cached locations
        if location.timestamp.timeIntervalSinceNow < -5.0 { return }
        
        currentLocation = location
        
        guard isTracking else { return }
        
        let newCoord = location.coordinate
        
        if let lastCoord = coordinates.last {
            let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            let distanceMeters = location.distance(from: lastLoc)
            // Add distance only if movement is reasonable (ignore tiny shifts)
            if distanceMeters > 1 {
                totalDistance += (distanceMeters / 1000.0) // Convert to km
                coordinates.append(newCoord)
            }
        } else {
            coordinates.append(newCoord)
        }
    }
}
