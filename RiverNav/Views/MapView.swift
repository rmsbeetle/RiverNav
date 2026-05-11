import MapLibre
import SwiftUI

struct MapView: UIViewRepresentable {
    var center: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62)
    var zoom: Double = 10

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.setCenter(center, zoomLevel: zoom, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        uiView.setCenter(center, zoomLevel: zoom, animated: true)
    }
}
