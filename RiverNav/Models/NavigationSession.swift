import Foundation

struct NavigationSession {
    enum State {
        case active, paused, finished
    }

    let routeId: UUID
    var state: State
    let startedAt: Date
    var pausedAt: Date?
}
