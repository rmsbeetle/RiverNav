import CoreLocation
import Foundation

struct Route: Identifiable, Hashable {
    let id: UUID
    var name: String
    var waypoints: [CLLocationCoordinate2D]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, waypoints: [CLLocationCoordinate2D] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.waypoints = waypoints
        self.createdAt = createdAt
    }

    static func == (lhs: Route, rhs: Route) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
