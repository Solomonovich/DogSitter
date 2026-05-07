import Foundation
import CoreLocation

class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var lastLocation: CLLocation?
    @Published var walkRoute: [CLLocationCoordinate2D] = []
    @Published var walkDistanceKm: Double = 0.0
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }
    
    func requestAuth() {
        manager.requestWhenInUseAuthorization()
        // Provide a default fallback location immediately (Tel Aviv) for mock testing if not available
        lastLocation = CLLocation(latitude: 32.0853, longitude: 34.7818)
    }
    
    func startWalk() {
        walkRoute.removeAll()
        walkDistanceKm = 0.0
        manager.startUpdatingLocation()
        print("Started Walk")
    }
    
    func stopWalk() {
        manager.stopUpdatingLocation()
        print("Stopped Walk")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        
        // Mock filter to prevent crazy jumps during simulation
        if location.horizontalAccuracy > 65 { return }
        
        let newCoord = location.coordinate
        
        if let last = walkRoute.last {
            let lastLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let distance = location.distance(from: lastLoc)
            // Add distance only if movement is reasonable (ignore 0)
            if distance > 1 {
                walkDistanceKm += distance / 1000.0
                walkRoute.append(newCoord)
            }
        } else {
            walkRoute.append(newCoord)
        }
    }
}
