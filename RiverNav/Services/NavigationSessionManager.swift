import CoreLocation
import Foundation

@Observable
final class NavigationSessionManager {

    // MARK: - Public state

    private(set) var session: NavigationSession?
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var distanceCovered: CLLocationDistance = 0
    private(set) var distanceRemaining: CLLocationDistance = 0
    private(set) var instantSpeed: CLLocationSpeed = 0   // m/s, from CLLocation.speed
    private(set) var averageSpeed: CLLocationSpeed = 0   // m/s, distanceCovered / elapsedTime

    /// True while session is active or paused (not finished / not started).
    var hasActiveSession: Bool {
        session.map { $0.state != .finished } ?? false
    }

    // MARK: - Session lifecycle

    func start(route: Route) {
        guard !hasActiveSession else { return }
        prepareRoute(route)
        session = NavigationSession(routeId: route.id, state: .active, startedAt: .now)
        elapsedTime = 0
        distanceCovered = 0
        distanceRemaining = totalRouteLength
        instantSpeed = 0
        averageSpeed = 0
        accumulatedTime = 0
        activeStart = .now
        startTimer()
    }

    func pause() {
        guard session?.state == .active else { return }
        session?.state = .paused
        session?.pausedAt = .now
        snapshotTime()
        stopTimer()
    }

    func resume() {
        guard session?.state == .paused else { return }
        session?.state = .active
        session?.pausedAt = nil
        activeStart = .now
        startTimer()
    }

    func finish() {
        guard hasActiveSession else { return }
        session?.state = .finished
        snapshotTime()
        stopTimer()
    }

    // MARK: - Location update (call from ContentView onChange)

    func updateLocation(_ location: CLLocation) {
        guard session?.state == .active else {
            instantSpeed = 0
            return
        }
        instantSpeed = location.speed >= 0 ? location.speed : 0
        projectOntoRoute(location.coordinate)
        averageSpeed = elapsedTime > 0 ? distanceCovered / elapsedTime : 0
    }

    // MARK: - Private: timing

    private var timerTask: Task<Void, Never>?
    private var accumulatedTime: TimeInterval = 0
    private var activeStart: Date?

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let start = activeStart else { break }
                elapsedTime = accumulatedTime + Date().timeIntervalSince(start)
                averageSpeed = elapsedTime > 0 ? distanceCovered / elapsedTime : 0
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Freezes accumulated time at the moment of pause / finish.
    private func snapshotTime() {
        if let start = activeStart {
            accumulatedTime += Date().timeIntervalSince(start)
            elapsedTime = accumulatedTime
            activeStart = nil
        }
    }

    // MARK: - Private: route geometry

    private var waypoints: [CLLocationCoordinate2D] = []
    /// cumulativeLengths[i] = total distance from waypoint[0] to waypoint[i].
    private var cumulativeLengths: [CLLocationDistance] = []
    private var totalRouteLength: CLLocationDistance = 0

    private func prepareRoute(_ route: Route) {
        waypoints = route.waypoints
        guard waypoints.count >= 2 else {
            cumulativeLengths = waypoints.isEmpty ? [] : [0]
            totalRouteLength = 0
            return
        }
        var acc: CLLocationDistance = 0
        var lengths: [CLLocationDistance] = [0]
        for i in 1..<waypoints.count {
            acc += haversine(waypoints[i - 1], waypoints[i])
            lengths.append(acc)
        }
        cumulativeLengths = lengths
        totalRouteLength = acc
    }

    // If the GPS position is farther than this from the route, progress is not updated.
    private static let offRouteThreshold: CLLocationDistance = 300

    /// Projects `pos` onto the polyline, updates distanceCovered / distanceRemaining.
    /// No-ops when the nearest point on the route is > offRouteThreshold metres away.
    private func projectOntoRoute(_ pos: CLLocationCoordinate2D) {
        guard waypoints.count >= 2 else { return }

        var bestIdx = 0
        var bestT: Double = 0
        var bestDistSq = Double.infinity

        for i in 0..<waypoints.count - 1 {
            let (ax, ay) = toMeters(origin: waypoints[i], target: waypoints[i + 1])
            let (px, py) = toMeters(origin: waypoints[i], target: pos)
            let lenSq = ax * ax + ay * ay
            let t = lenSq == 0 ? 0.0 : max(0, min(1, (px * ax + py * ay) / lenSq))
            let ex = px - t * ax
            let ey = py - t * ay
            let dSq = ex * ex + ey * ey
            if dSq < bestDistSq {
                bestDistSq = dSq
                bestIdx = i
                bestT = t
            }
        }

        // Accurate geodesic check: interpolate the projected coordinate and measure real distance.
        // (flat-Earth toMeters() can be unreliable for points hundreds of km away)
        let p1 = waypoints[bestIdx], p2 = waypoints[bestIdx + 1]
        let projCoord = CLLocationCoordinate2D(
            latitude:  p1.latitude  + bestT * (p2.latitude  - p1.latitude),
            longitude: p1.longitude + bestT * (p2.longitude - p1.longitude)
        )
        let realDist = CLLocation(latitude: pos.latitude, longitude: pos.longitude)
            .distance(from: CLLocation(latitude: projCoord.latitude, longitude: projCoord.longitude))
        guard realDist <= Self.offRouteThreshold else { return }

        let segLen = haversine(waypoints[bestIdx], waypoints[bestIdx + 1])
        let covered = cumulativeLengths[bestIdx] + bestT * segLen
        distanceCovered = covered
        distanceRemaining = max(0, totalRouteLength - covered)
    }

    /// Returns the minimum geodesic distance from `location` to any point on `route`'s polyline.
    /// Used by RouteView to warn the user before starting if they are far from the route.
    func minimumDistance(to route: Route, from location: CLLocation) -> CLLocationDistance {
        let wps = route.waypoints
        guard wps.count >= 2 else {
            return wps.isEmpty ? .infinity :
                location.distance(from: CLLocation(latitude: wps[0].latitude, longitude: wps[0].longitude))
        }
        var minDist = CLLocationDistance.infinity
        let pos = location.coordinate
        for i in 0..<wps.count - 1 {
            let (ax, ay) = toMeters(origin: wps[i], target: wps[i + 1])
            let (px, py) = toMeters(origin: wps[i], target: pos)
            let lenSq = ax * ax + ay * ay
            let t = lenSq == 0 ? 0.0 : max(0, min(1, (px * ax + py * ay) / lenSq))
            let projCoord = CLLocationCoordinate2D(
                latitude:  wps[i].latitude  + t * (wps[i + 1].latitude  - wps[i].latitude),
                longitude: wps[i].longitude + t * (wps[i + 1].longitude - wps[i].longitude)
            )
            let dist = location.distance(from: CLLocation(latitude: projCoord.latitude, longitude: projCoord.longitude))
            minDist = min(minDist, dist)
        }
        return minDist
    }

    /// Equirectangular approximation: returns (dx, dy) in metres from `origin` to `target`.
    /// Accurate to < 0.1 % for segments up to ~50 km — sufficient for river navigation.
    private func toMeters(origin: CLLocationCoordinate2D,
                          target: CLLocationCoordinate2D) -> (Double, Double) {
        let R = 6_371_000.0
        let φ = origin.latitude * .pi / 180
        let dx = (target.longitude - origin.longitude) * .pi / 180 * R * cos(φ)
        let dy = (target.latitude - origin.latitude) * .pi / 180 * R
        return (dx, dy)
    }

    private func haversine(_ a: CLLocationCoordinate2D,
                           _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
