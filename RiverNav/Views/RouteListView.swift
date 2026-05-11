import SwiftUI
import UniformTypeIdentifiers

// MARK: - ViewModel

@Observable
private final class RouteListViewModel {
    var routes: [Route] = []

    func loadRoutes() async {
        routes = (try? await RouteStore.shared.loadAll()) ?? []
    }

    func savePendingRoute(name: String, data: Data) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let waypoints = GPXParser().parse(data: data)
        let route = Route(name: trimmed, waypoints: waypoints)
        try? await RouteStore.shared.save(route)
        await loadRoutes()
    }

    func delete(_ route: Route) async {
        try? await RouteStore.shared.delete(id: route.id)
        await loadRoutes()
    }
}

// MARK: - View

struct RouteListView: View {
    @State private var viewModel = RouteListViewModel()
    @State private var isShowingDocumentPicker = false
    @State private var isShowingNameAlert = false
    @State private var isShowingRenameAlert = false
    @State private var pendingGPXData: Data?
    @State private var routeToRename: Route?
    @State private var editingName = ""

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
                        isShowingDocumentPicker = true
                    }
                }
            }
            .fileImporter(
                isPresented: $isShowingDocumentPicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "gpx") ?? .xml,
                    .xml
                ],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result,
                      let url = urls.first,
                      url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                guard let data = try? Data(contentsOf: url) else { return }
                pendingGPXData = data
                editingName = url.deletingPathExtension().lastPathComponent
                isShowingNameAlert = true
            }
            .alert("Новый маршрут", isPresented: $isShowingNameAlert) {
                TextField("Название маршрута", text: $editingName)
                Button("Сохранить") {
                    guard let data = pendingGPXData else { return }
                    let name = editingName
                    pendingGPXData = nil
                    editingName = ""
                    Task { await viewModel.savePendingRoute(name: name, data: data) }
                }
                Button("Отмена", role: .cancel) {
                    pendingGPXData = nil
                }
            }
            .alert("Переименовать", isPresented: $isShowingRenameAlert) {
                TextField("Название маршрута", text: $editingName)
                Button("Сохранить") {
                    guard let route = routeToRename else { return }
                    let name = editingName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    // Synchronous in-memory update — batched with @State mutations,
                    // guaranteed to trigger a SwiftUI re-render before disk I/O.
                    if let idx = viewModel.routes.firstIndex(where: { $0.id == route.id }) {
                        var updated = viewModel.routes
                        updated[idx].name = name
                        viewModel.routes = updated
                    }
                    routeToRename = nil
                    editingName = ""
                    let routeId = route.id
                    Task { try? await RouteStore.shared.rename(id: routeId, newName: name) }
                }
                Button("Отмена", role: .cancel) {
                    routeToRename = nil
                }
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
                        routeToRename = route
                        editingName = route.name
                        isShowingRenameAlert = true
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
            RouteView(route: route)
        }
    }
}
