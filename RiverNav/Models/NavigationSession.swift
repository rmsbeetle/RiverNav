import Foundation

struct NavigationSession {
    enum State {
        case idle, active, paused
    }

    let routeId: UUID
    var state: State
    let startedAt: Date
    var pausedAt: Date?
}
