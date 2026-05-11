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

    func rename(_ route: Route, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? await RouteStore.shared.rename(id: route.id, newName: trimmed)
        if let idx = routes.firstIndex(where: { $0.id == route.id }) {
            var updated = routes
            updated[idx].name = trimmed
            routes = updated
        }
    }
}

// MARK: - View

struct RouteListView: View {
    @State private var viewModel = RouteListViewModel()

    // All presentation state lives in @State — reliable @State bindings, no @Bindable needed.
    @State private var isShowingDocumentPicker = false
    @State private var isShowingNameAlert = false
    @State private var isShowingRenameAlert = false
    @State private var pendingGPXData: Data?
    @State private var routeToRename: Route?
    @State private var editingName = ""
    @State private var debugInfo = ""

    var body: some View {
        ZStack(alignment: .bottom) {
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
                editingName = ""
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
                    let name = editingName
                    debugInfo = "route='\(route.name)' | editing='\(editingName)' | captured='\(name)'"
                    routeToRename = nil
                    editingName = ""
                    Task {
                        await viewModel.rename(route, to: name)
                        debugInfo += " | routes=\(viewModel.routes.map(\.name))"
                    }
                }
                Button("Отмена", role: .cancel) {
                    routeToRename = nil
                }
            }
            .task { await viewModel.loadRoutes() }
        }
        if !debugInfo.isEmpty {
            Text(debugInfo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
                .onTapGesture { debugInfo = "" }
        }
        } // ZStack
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
