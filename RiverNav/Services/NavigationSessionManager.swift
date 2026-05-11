import Foundation

@Observable
final class NavigationSessionManager {
    private(set) var currentSession: NavigationSession?

    var hasActiveSession: Bool { currentSession != nil }

    func start(route: Route) {
        guard currentSession == nil else { return }
        currentSession = NavigationSession(routeId: route.id, state: .active, startedAt: .now)
    }

    func stop() {
        currentSession = nil
    }
}
