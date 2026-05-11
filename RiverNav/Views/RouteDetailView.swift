import SwiftUI

struct RouteDetailView: View {
    let route: Route

    var body: some View {
        Text("\(route.waypoints.count) точек маршрута")
            .foregroundStyle(.secondary)
            .navigationTitle(route.name)
            .navigationBarTitleDisplayMode(.large)
    }
}
