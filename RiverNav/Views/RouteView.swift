import CoreLocation
import MapLibre
import SwiftUI

// MARK: - RouteView

struct RouteView: View {
    let route: Route

    @Environment(NavigationSessionManager.self) private var sessionManager
    @Environment(LocationService.self) private var locationService

    @State private var isShowingFinishAlert = false
    @State private var isShowingFarAlert = false
    @State private var distanceToRoute: CLLocationDistance = 0

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
                Button("Старт") { attemptStart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationService.requestPermission()
            locationService.startUpdating()
        }
        .alert("Завершить маршрут?", isPresented: $isShowingFinishAlert) {
            Button("Завершить", role: .destructive) { sessionManager.finish() }
            Button("Продолжить", role: .cancel) {}
        } message: {
            Text("До конца маршрута осталось \(formatDist(sessionManager.distanceRemaining)).")
        }
        .alert("Далеко от маршрута", isPresented: $isShowingFarAlert) {
            Button("Начать всё равно") { sessionManager.start(route: route) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы находитесь в \(formatDist(distanceToRoute)) от ближайшей точки маршрута.")
        }
    }

    // MARK: - HUD

    private var navigationHUD: some View {
        VStack(spacing: 0) {
            metricsSection
            Divider()
            controlsSection
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
    }

    private var metricsSection: some View {
        VStack(spacing: 0) {
            // Row 1: elapsed time · instant speed · average speed
            HStack(spacing: 0) {
                MetricCell(label: "Время",       value: formattedTime)
                MetricDivider()
                MetricCell(label: "Скорость",    value: formatSpeed(sessionManager.instantSpeed))
                MetricDivider()
                MetricCell(label: "Ср. скорость", value: formatSpeed(sessionManager.averageSpeed))
            }
            Divider().padding(.horizontal)
            // Row 2: covered · remaining
            HStack(spacing: 0) {
                MetricCell(label: "Пройдено", value: formatDist(sessionManager.distanceCovered))
                MetricDivider()
                MetricCell(label: "Осталось", value: formatDist(sessionManager.distanceRemaining))
            }
        }
        .padding(.vertical, 12)
    }

    private var controlsSection: some View {
        HStack(spacing: 12) {
            if sessionManager.session?.state == .paused {
                Button("Продолжить") { sessionManager.resume() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            } else {
                Button("Пауза") { sessionManager.pause() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            Button("Завершить") { confirmFinish() }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func attemptStart() {
        if let location = locationService.currentLocation {
            let dist = sessionManager.minimumDistance(to: route, from: location)
            if dist > 200 {
                distanceToRoute = dist
                isShowingFarAlert = true
                return
            }
        }
        sessionManager.start(route: route)
    }

    private func confirmFinish() {
        // Ask only if there's meaningful distance left (> 100 m)
        if sessionManager.distanceRemaining > 100 {
            isShowingFinishAlert = true
        } else {
            sessionManager.finish()
        }
    }

    // MARK: - Formatting

    private var formattedTime: String {
        let t = Int(sessionManager.elapsedTime)
        let h = t / 3600, m = t % 3600 / 60, s = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private func formatSpeed(_ ms: CLLocationSpeed) -> String {
        String(format: "%.1f км/ч", ms * 3.6)
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
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct MetricDivider: View {
    var body: some View { Divider().frame(height: 36) }
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
                edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 200, right: 40),
                animated: false
            )
        }
    }
}
