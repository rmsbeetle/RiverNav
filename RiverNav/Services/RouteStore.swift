import CoreLocation
import Foundation

actor RouteStore {
    static let shared = RouteStore()

    private let routesDir: URL
    private let metadataURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Storage types

    private struct StoredCoordinate: Codable {
        let latitude: Double
        let longitude: Double
    }

    private struct RouteMetadata: Codable {
        let id: UUID
        var name: String
        let createdAt: Date
        let waypointCount: Int
    }

    // MARK: - Init

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        routesDir = documents.appendingPathComponent("routes", isDirectory: true)
        metadataURL = routesDir.appendingPathComponent("metadata.json")
        try? FileManager.default.createDirectory(at: routesDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func save(_ route: Route) throws {
        let stored = route.waypoints.map { StoredCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        try encoder.encode(stored).write(to: coordinateURL(for: route.id), options: .atomic)

        var list = (try? loadMetadata()) ?? []
        list.removeAll { $0.id == route.id }
        list.append(RouteMetadata(id: route.id, name: route.name, createdAt: route.createdAt, waypointCount: route.waypoints.count))
        try saveMetadata(list)
    }

    func delete(id: UUID) throws {
        try? FileManager.default.removeItem(at: coordinateURL(for: id))
        var list = (try? loadMetadata()) ?? []
        list.removeAll { $0.id == id }
        try saveMetadata(list)
    }

    func rename(id: UUID, newName: String) throws {
        var list = (try? loadMetadata()) ?? []
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].name = newName
        try saveMetadata(list)
    }

    func loadAll() throws -> [Route] {
        try loadMetadata().map { meta in
            let stored = try decoder.decode(
                [StoredCoordinate].self,
                from: Data(contentsOf: coordinateURL(for: meta.id))
            )
            return Route(
                id: meta.id,
                name: meta.name,
                waypoints: stored.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                createdAt: meta.createdAt
            )
        }
    }

    // MARK: - Private helpers

    private func coordinateURL(for id: UUID) -> URL {
        routesDir.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadMetadata() throws -> [RouteMetadata] {
        try decoder.decode([RouteMetadata].self, from: Data(contentsOf: metadataURL))
    }

    private func saveMetadata(_ list: [RouteMetadata]) throws {
        try encoder.encode(list).write(to: metadataURL, options: .atomic)
    }
}
