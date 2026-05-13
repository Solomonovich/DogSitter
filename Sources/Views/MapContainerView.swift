import SwiftUI
import MapKit

struct MapContainerView: UIViewRepresentable {
    @Binding var centerCoordinate: CLLocationCoordinate2D?
    var annotations: [MKPointAnnotation] = []
    var route: [CLLocationCoordinate2D] = []
    var isFollowingUser: Bool = false
    var selectedAnnotationID: String?
    
    // Binding for user clicking a pin
    var onAnnotationTapped: ((MKPointAnnotation) -> Void)?
    var onMapTapped: (() -> Void)?
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapContainerView
        
        init(_ parent: MapContainerView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            } else if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pointAnn = annotation as? MKPointAnnotation else { return nil }
            let identifier = "PostPin"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if view == nil {
                view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = false
            } else {
                view?.annotation = annotation
            }
            
            updateAnnotationView(view!, for: pointAnn, isSelected: pointAnn.subtitle == parent.selectedAnnotationID)
            return view
        }
        
        func updateAnnotationView(_ view: MKAnnotationView, for annotation: MKPointAnnotation, isSelected: Bool) {
            let size: CGFloat = isSelected ? 44 : 36
            let bgColor = isSelected ? UIColor(red: 74/255, green: 144/255, blue: 217/255, alpha: 1.0) : .white
            let iconColor = isSelected ? .white : UIColor(red: 74/255, green: 144/255, blue: 217/255, alpha: 1.0)
            
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { ctx in
                ctx.cgContext.setFillColor(bgColor.cgColor)
                let shadowRadius: CGFloat = isSelected ? 6 : 4
                let shadowOpacity: Float = isSelected ? 0.4 : 0.2
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: shadowRadius, color: UIColor.black.withAlphaComponent(CGFloat(shadowOpacity)).cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: size-4, height: size-4))
                
                if let pawImage = UIImage(systemName: "pawprint.fill")?.withTintColor(iconColor, renderingMode: .alwaysOriginal) {
                    let pawSize = size * 0.5
                    let rect = CGRect(x: (size - pawSize)/2, y: (size - pawSize)/2, width: pawSize, height: pawSize)
                    pawImage.draw(in: rect)
                }
            }
            view.image = image
            // Ensure selected pin stays on top
            view.layer.zPosition = isSelected ? 1 : 0
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation as? MKPointAnnotation {
                parent.onAnnotationTapped?(annotation)
            }
            mapView.deselectAnnotation(view.annotation, animated: true)
        }
        
        @objc func handleMapTap(_ sender: UITapGestureRecognizer) {
            // Check if we hit an annotation view, if so ignore
            let location = sender.location(in: sender.view)
            if let mapView = sender.view as? MKMapView {
                let hitView = mapView.hitTest(location, with: nil)
                if hitView is MKAnnotationView { return }
                parent.onMapTapped?()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        // Setup OpenStreetMap Tile Overlay
        let template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        let overlay = MKTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = true
        mapView.addOverlay(overlay, level: .aboveLabels)
        
        mapView.showsUserLocation = true
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tap)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        mapView.layoutMargins = UIEdgeInsets(top: 150, left: 0, bottom: 400, right: 0)
        
        // Update Annotations
        let currentAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(currentAnnotations)
        mapView.addAnnotations(annotations)
        
        // Update Overlays (Polylines)
        let currentPolylines = mapView.overlays.filter { $0 is MKPolyline }
        mapView.removeOverlays(currentPolylines)
        if !route.isEmpty {
            let polyline = MKPolyline(coordinates: route, count: route.count)
            mapView.addOverlay(polyline)
        }
        
        // Update visible annotations selection state with a small delay to debounce
        let currentSelectedID = self.selectedAnnotationID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Force reset ALL to normal first
            for annotation in mapView.annotations {
                if let pointAnn = annotation as? MKPointAnnotation,
                   let view = mapView.view(for: annotation) {
                    view.transform = .identity
                    context.coordinator.updateAnnotationView(view, for: pointAnn, isSelected: false)
                }
            }
            
            // Then after resetting all, animate the selected pin
            for annotation in mapView.annotations {
                if let pointAnn = annotation as? MKPointAnnotation,
                   let view = mapView.view(for: annotation) {
                    if pointAnn.subtitle == currentSelectedID {
                        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: [], animations: {
                            context.coordinator.updateAnnotationView(view, for: pointAnn, isSelected: true)
                            view.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                        })
                    }
                }
            }
        }
        
        // Manage camera
        if isFollowingUser, let userLoc = mapView.userLocation.location?.coordinate {
            let region = MKCoordinateRegion(center: userLoc, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
        } else if let center = centerCoordinate {
            let currentCenter = mapView.centerCoordinate
            let distance = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
            
            if distance > 100 {
                mapView.setCenter(center, animated: true)
            }
        } else {
            // Default Israel view
            if mapView.region.span.latitudeDelta > 10.0 {
                let israelCenter = CLLocationCoordinate2D(latitude: 31.0461, longitude: 34.8516)
                let region = MKCoordinateRegion(center: israelCenter, latitudinalMeters: 100000, longitudinalMeters: 100000)
                mapView.setRegion(region, animated: false)
            }
        }
    }
}
