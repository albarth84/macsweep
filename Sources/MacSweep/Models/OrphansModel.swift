import Foundation
import Observation

@MainActor
@Observable
final class OrphansModel {
    var items: [OrphanItem] = []
    var isScanning = false
    var hasScanned = false
    var isRemoving = false
    var minimumConfidence: OrphanConfidence = .medium
    var lastResult: DeletionResult?

    var visibleIndices: [Int] {
        items.indices.filter { items[$0].confidence >= minimumConfidence }
    }

    var selectedItems: [OrphanItem] {
        items.filter { $0.selected && $0.confidence >= minimumConfidence }
    }

    var selectedTotal: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            // Le app di sistema contano come installate (le loro preferenze non sono orfane).
            let installed = AppScanner.installedApps(includeSystem: true)
            let found = OrphanFinder.find(installed: installed)
            await MainActor.run {
                self.items = found
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func setAllVisible(_ selected: Bool) {
        for i in visibleIndices { items[i].selected = selected }
    }

    func removeSelected() {
        let chosen = selectedItems
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
        let sizes = Dictionary(items.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
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
        items.removeAll { removed.contains($0.url.path) }
    }
}
