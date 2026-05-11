import CoreLocation
import MapLibre
import SwiftUI

// MARK: - RouteView

struct RouteView: View {
    let route: Route

    @Environment(NavigationSessionManager.self) private var sessionManager
    @Environment(LocationService.self) private var locationService

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteMapView(
                route: route,
                followUser: sessionManager.session?.state == .active
            )
            .ignoresSafeArea()

            if sessionManager.hasActiveSession {
                navigationHUD
            } else {
                Button("Старт") {
                    sessionManager.start(route: route)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationService.requestPermission()
            locationService.startUpdating()
        }
    }

    // MARK: - Navigation HUD

    private var navigationHUD: some View {
        VStack(spacing: 12) {
            HStack {
                MetricCell(label: "Время",    value: formattedTime)
                MetricDivider()
                MetricCell(label: "Пройдено", value: formatDist(sessionManager.distanceCovered))
                MetricDivider()
                MetricCell(label: "Осталось", value: formatDist(sessionManager.distanceRemaining))
                MetricDivider()
                MetricCell(label: "Скорость", value: formattedSpeed)
            }

            HStack(spacing: 16) {
                if sessionManager.session?.state == .paused {
                    Button("Продолжить") { sessionManager.resume() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Пауза") { sessionManager.pause() }
                        .buttonStyle(.bordered)
                }
                Button("Завершить", role: .destructive) { sessionManager.finish() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 32)
    }

    // MARK: - Formatting

    private var formattedTime: String {
        let t = Int(sessionManager.elapsedTime)
        let h = t / 3600, m = t % 3600 / 60, s = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private var formattedSpeed: String {
        String(format: "%.1f км/ч", sessionManager.instantSpeed * 3.6)
    }

    private func formatDist(_ d: CLLocationDistance) -> String {
        d >= 1000
            ? String(format: "%.1f км", d / 1000)
            : String(format: "%.0f м", d)
    }
}

// MARK: - Metric subviews

private struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .monospaced).bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MetricDivider: View {
    var body: some View { Divider().frame(height: 32) }
}

// MARK: - RouteMapView

private struct RouteMapView: UIViewRepresentable {
    let route: Route
    let followUser: Bool

    private static let osmStyleURL: URL = {
        let json = """
        {
          "version": 8,
          "sources": {
            "osm": {
              "type": "raster",
              "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
              "tileSize": 256,
              "attribution": "© OpenStreetMap contributors"
            }
          },
          "layers": [
            { "id": "osm-layer", "type": "raster", "source": "osm" }
          ]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rivernav-osm-style.json")
        try? json.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }()

    func makeCoordinator() -> Coordinator { Coordinator(route: route) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: Self.osmStyleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        // Switch to .follow when a session is active, back to .none otherwise.
        uiView.userTrackingMode = followUser ? .follow : .none
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private let route: Route

        init(route: Route) { self.route = route }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            drawPolyline(style: style)
            zoomToBounds(mapView)
        }

        private func drawPolyline(style: MLNStyle) {
            let waypoints = route.waypoints
            guard waypoints.count >= 2 else { return }

            var coords = waypoints
            let polyline = coords.withUnsafeMutableBufferPointer { buf in
                MLNPolyline(coordinates: buf.baseAddress!, count: UInt(buf.count))
            }

            let source = MLNShapeSource(identifier: "route-source", shape: polyline, options: nil)
            style.addSource(source)

            let layer = MLNLineStyleLayer(identifier: "route-layer", source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            layer.lineWidth = NSExpression(forConstantValue: NSNumber(value: 3.0))
            layer.lineJoin  = NSExpression(forConstantValue: "round")
            layer.lineCap   = NSExpression(forConstantValue: "round")
            style.addLayer(layer)
        }

        private func zoomToBounds(_ mapView: MLNMapView) {
            let coords = route.waypoints
            guard !coords.isEmpty else { return }
            guard coords.count > 1 else {
                mapView.setCenter(coords[0], zoomLevel: 14, animated: false)
                return
            }

            var minLat = coords[0].latitude, maxLat = coords[0].latitude
            var minLon = coords[0].longitude, maxLon = coords[0].longitude
            for c in coords.dropFirst() {
                minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
                minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
            }

            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
            )
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 180, right: 40),
                animated: false
            )
        }
    }
}
