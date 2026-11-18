import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class AppsModel {
    var apps: [AppInfo] = []
    var sizes: [String: Int64] = [:]
    var isLoading = false
    var searchText = ""
    var selectedID: String?

    var leftovers: [LeftoverItem] = []
    var isSearchingLeftovers = false
    var isRemoving = false
    var lastResult: DeletionResult?

    enum SortOrder: String, CaseIterable, Identifiable {
        case name, size
        var id: String { rawValue }
        var title: String { self == .name ? "Nome" : "Dimensione" }
        var symbol: String { self == .name ? "textformat" : "arrow.down.circle" }
    }

    /// Ordinamento scelto, ricordato tra un avvio e l'altro.
    var sortOrder: SortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "appsSortOrder") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "appsSortOrder") }
    }

    var filteredApps: [AppInfo] {
        let visible = searchText.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
        switch sortOrder {
        case .name:
            return visible // già in ordine alfabetico
        case .size:
            // Le app ancora da misurare finiscono in fondo.
            return visible.sorted { (sizes[$0.id] ?? -1, $1.name) > (sizes[$1.id] ?? -1, $0.name) }
        }
    }

    var largestSize: Int64 { sizes.values.max() ?? 0 }

    var selectedApp: AppInfo? { apps.first { $0.id == selectedID } }

    var selectedTotal: Int64 { leftovers.filter(\.selected).reduce(0) { $0 + $1.size } }

    var isSelectedAppRunning: Bool {
        guard let app = selectedApp, !app.bundleID.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let apps = AppScanner.installedApps()
            await MainActor.run {
                self.apps = apps
                self.isLoading = false
                if let id = self.selectedID, !apps.contains(where: { $0.id == id }) {
                    self.selectedID = nil
                    self.leftovers = []
                }
            }
            // Dimensioni calcolate dopo, in background, per non bloccare la lista.
            for app in apps {
                let size = FileSize.allocated(app.url)
                await MainActor.run { self.sizes[app.id] = size }
            }
        }
    }

    func select(_ id: String?) {
        selectedID = id
        leftovers = []
        guard let app = selectedApp else { return }
        isSearchingLeftovers = true
        Task.detached(priority: .userInitiated) {
            let found = LeftoverFinder.find(for: app)
            await MainActor.run {
                guard self.selectedID == app.id else { return }
                self.leftovers = found
                self.isSearchingLeftovers = false
            }
        }
    }

    func setAll(_ selected: Bool) {
        for i in leftovers.indices { leftovers[i].selected = selected }
    }

    func quitSelectedApp() {
        guard let app = selectedApp else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).forEach { $0.terminate() }
    }

    func removeSelected() {
        let chosen = leftovers.filter(\.selected)
        guard !chosen.isEmpty else { return }
        isRemoving = true
        let sizes = Dictionary(chosen.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        Task.detached(priority: .userInitiated) {
            let result = Trash.move(chosen.map(\.url), sizes: sizes)
            let final = result
            await MainActor.run { self.finish(final) }
        }
    }

    func retryWithAdmin(_ urls: [URL]) {
        let sizes = Dictionary(leftovers.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        lastResult = nil
        isRemoving = true
        Task.detached(priority: .userInitiated) {
            var result = Trash.moveWithAdminPrivileges(urls)
            result.freed = result.removed.reduce(0) { $0 + (sizes[$1] ?? 0) }
            let final = result
            await MainActor.run { self.finish(final) }
        }
    }

    private func finish(_ result: DeletionResult) {
        isRemoving = false
        lastResult = result
        let removed = Set(result.removed.map(\.path))
        leftovers.removeAll { removed.contains($0.url.path) }
        if let app = selectedApp, removed.contains(app.url.path) {
            apps.removeAll { $0.id == app.id }
        }
    }
}
