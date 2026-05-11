import SwiftUI

// MARK: - ViewModel

@Observable
private final class RouteListViewModel {
    var routes: [Route] = []
    var isShowingDocumentPicker = false
    var isShowingNameAlert = false
    var isShowingRenameAlert = false
    var newRouteName = ""
    var pendingGPXData: Data?
    var routeToRename: Route?

    func loadRoutes() async {
        routes = (try? await RouteStore.shared.loadAll()) ?? []
    }

    func savePendingRoute() async {
        let trimmed = newRouteName.trimmingCharacters(in: .whitespaces)
        guard let data = pendingGPXData, !trimmed.isEmpty else { return }
        let waypoints = GPXParser().parse(data: data)
        let route = Route(name: trimmed, waypoints: waypoints)
        try? await RouteStore.shared.save(route)
        pendingGPXData = nil
        newRouteName = ""
        await loadRoutes()
    }

    func delete(_ route: Route) async {
        try? await RouteStore.shared.delete(id: route.id)
        await loadRoutes()
    }

    func startRename(_ route: Route) {
        routeToRename = route
        newRouteName = route.name
        isShowingRenameAlert = true
    }

    func renameRoute() async {
        let trimmed = newRouteName.trimmingCharacters(in: .whitespaces)
        guard let route = routeToRename, !trimmed.isEmpty else { return }
        try? await RouteStore.shared.rename(id: route.id, newName: trimmed)
        routeToRename = nil
        newRouteName = ""
        await loadRoutes()
    }
}

// MARK: - View

struct RouteListView: View {
    @State private var viewModel = RouteListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.routes.isEmpty {
                    emptyState
                } else {
                    routeList
                }
            }
            .navigationTitle("Маршруты")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить", systemImage: "plus") {
                        viewModel.isShowingDocumentPicker = true
                    }
                }
            }
            .sheet(isPresented: $viewModel.isShowingDocumentPicker, onDismiss: {
                if viewModel.pendingGPXData != nil {
                    viewModel.newRouteName = ""
                    viewModel.isShowingNameAlert = true
                }
            }) {
                DocumentPicker(isPresented: $viewModel.isShowingDocumentPicker) { data in
                    viewModel.pendingGPXData = data
                }
            }
            .alert("Новый маршрут", isPresented: $viewModel.isShowingNameAlert) {
                TextField("Название маршрута", text: $viewModel.newRouteName)
                Button("Сохранить") { Task { await viewModel.savePendingRoute() } }
                Button("Отмена", role: .cancel) { viewModel.pendingGPXData = nil }
            }
            .alert("Переименовать", isPresented: $viewModel.isShowingRenameAlert) {
                TextField("Название маршрута", text: $viewModel.newRouteName)
                Button("Сохранить") { Task { await viewModel.renameRoute() } }
                Button("Отмена", role: .cancel) { viewModel.routeToRename = nil }
            }
            .task { await viewModel.loadRoutes() }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "Нет маршрутов",
            systemImage: "map",
            description: Text("Нажмите + и выберите GPX-файл")
        )
    }

    private var routeList: some View {
        List {
            ForEach(viewModel.routes) { route in
                NavigationLink(value: route) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name)
                            .font(.headline)
                        Text(
                            "\(route.waypoints.count) точек · " +
                            route.createdAt.formatted(date: .abbreviated, time: .omitted)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .contextMenu {
                    Button("Переименовать", systemImage: "pencil") {
                        viewModel.startRename(route)
                    }
                    Button("Удалить", systemImage: "trash", role: .destructive) {
                        Task { await viewModel.delete(route) }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Удалить", role: .destructive) {
                        Task { await viewModel.delete(route) }
                    }
                }
            }
        }
        .navigationDestination(for: Route.self) { route in
            RouteDetailView(route: route)
        }
    }
}
