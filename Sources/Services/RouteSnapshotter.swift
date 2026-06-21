import Foundation
import MapKit
import UIKit

/// Renders a route (list of coordinates) to a static map image with the path drawn on
/// top. Shared by the finished-walk chat bubble and the post-walk recap card.
enum RouteSnapshotter {
    static func makeRouteSnapshot(coordinates: [CLLocationCoordinate2D],
                                  size: CGSize,
                                  strokeColor: UIColor,
                                  completion: @escaping (UIImage?) -> Void) {
        guard coordinates.count > 1 else { completion(nil); return }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        var mapRect = polyline.boundingMapRect
        mapRect = mapRect.insetBy(dx: -mapRect.width * 0.2, dy: -mapRect.height * 0.2)

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(mapRect)
        options.size = size

        MKMapSnapshotter(options: options).start { snapshot, error in
            guard let snapshot = snapshot, error == nil else {
                completion(nil)
                return
            }

            let image = snapshot.image
            UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
            image.draw(at: .zero)

            if let context = UIGraphicsGetCurrentContext() {
                context.setLineWidth(4.0)
                context.setStrokeColor(strokeColor.cgColor)
                let points = coordinates.map { snapshot.point(for: $0) }
                if let first = points.first {
                    context.move(to: first)
                    for point in points.dropFirst() { context.addLine(to: point) }
                    context.strokePath()
                }
            }

            let finalImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            DispatchQueue.main.async { completion(finalImage) }
        }
    }
}
