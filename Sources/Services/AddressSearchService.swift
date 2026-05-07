import Foundation
import MapKit

class AddressSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchQuery = "" {
        didSet {
            completer.queryFragment = searchQuery
        }
    }
    @Published var completions: [MKLocalSearchCompletion] = []
    private var completer: MKLocalSearchCompleter
    
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Israel rough bounding box
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.0461, longitude: 34.8516),
            latitudinalMeters: 500000,
            longitudinalMeters: 500000
        )
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        self.completions = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // print ignored or debug only
    }
    
    func geocode(completion: MKLocalSearchCompletion, result: @escaping (CLLocationCoordinate2D?) -> Void) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            result(response?.mapItems.first?.placemark.coordinate)
        }
    }
}
