import SwiftUI
import MapKit

struct MapContainerView: UIViewRepresentable {
    var centerCoordinate: CLLocationCoordinate2D?
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
            let size: CGFloat = isSelected ? 48 : 36
            let bgColor = isSelected ? UIColor(red: 40/255, green: 100/255, blue: 200/255, alpha: 1.0) : .white
            let iconColor = isSelected ? .white : UIColor(red: 74/255, green: 144/255, blue: 217/255, alpha: 1.0)
            
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            let image = renderer.image { ctx in
                ctx.cgContext.setFillColor(bgColor.cgColor)
                ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.2).cgColor)
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
        
        // Update visible annotations selection state
        for annotation in mapView.annotations {
            if let pointAnn = annotation as? MKPointAnnotation,
               let view = mapView.view(for: annotation) {
                let isSelected = pointAnn.subtitle == selectedAnnotationID
                context.coordinator.updateAnnotationView(view, for: pointAnn, isSelected: isSelected)
            }
        }
        
        // Manage camera
        if isFollowingUser, let userLoc = mapView.userLocation.location?.coordinate {
            let region = MKCoordinateRegion(center: userLoc, latitudinalMeters: 500, longitudinalMeters: 500)
            mapView.setRegion(region, animated: true)
        } else if let center = centerCoordinate {
            if selectedAnnotationID != nil {
                // Zoom in on selected post
                let region = MKCoordinateRegion(center: center, latitudinalMeters: 2000, longitudinalMeters: 2000)
                mapView.setRegion(region, animated: true)
            } else {
                // Zoom out to show 10km radius for all posts
                let region = MKCoordinateRegion(center: center, latitudinalMeters: 20000, longitudinalMeters: 20000)
                mapView.setRegion(region, animated: true)
            }
        } else {
            // Default Israel view
            if mapView.region.span.latitudeDelta > 10.0 {
                let israelCenter = CLLocationCoordinate2D(latitude: 31.0461, longitude: 34.8516)
                let region = MKCoordinateRegion(center: israelCenter, latitudinalMeters: 200000, longitudinalMeters: 200000)
                mapView.setRegion(region, animated: false)
            }
        }
    }
}
