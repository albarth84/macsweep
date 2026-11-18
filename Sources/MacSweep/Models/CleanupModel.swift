import Foundation
import Observation

@MainActor
@Observable
final class CleanupModel {
    let categories = CleanupCategory.all
    var items: [String: [CleanupItem]] = [:]
    var analyzing: Set<String> = []
    var isCleaning = false
    var lastResult: DeletionResult?

    var hasAnalyzed: Bool { !items.isEmpty }

    func total(_ categoryID: String) -> Int64 {
        items[categoryID, default: []].reduce(0) { $0 + $1.size }
    }

    var selectedTotal: Int64 {
        items.values.joined().filter(\.selected).reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int { items.values.joined().filter(\.selected).count }

    func analyzeAll() {
        for category in categories { analyze(category) }
    }

    func analyze(_ category: CleanupCategory) {
        guard !analyzing.contains(category.id) else { return }
        analyzing.insert(category.id)
        Task.detached(priority: .userInitiated) {
            let found = CleanupScanner.items(for: category)
            await MainActor.run {
                // Le categorie "sicure" vengono preselezionate.
                self.items[category.id] = found.map { item in
                    var copy = item
                    copy.selected = category.risk == .safe
                    return copy
                }
                self.analyzing.remove(category.id)
            }
        }
    }

    func setAll(_ categoryID: String, selected: Bool) {
        guard var list = items[categoryID] else { return }
        for i in list.indices { list[i].selected = selected }
        items[categoryID] = list
    }

    func isAllSelected(_ categoryID: String) -> Bool {
        let list = items[categoryID, default: []]
        return !list.isEmpty && list.allSatisfy(\.selected)
    }

    func clean() {
        isCleaning = true
        let snapshot = items
        let categories = self.categories
        Task.detached(priority: .userInitiated) {
            var result = DeletionResult()
            for category in categories {
                for item in snapshot[category.id, default: []] where item.selected {
                    let partial: DeletionResult
                    if item.contentsOnly {
                        partial = Trash.moveContents(of: item.url)
                    } else if category.permanent {
                        partial = Trash.deletePermanently([item.url], sizes: [item.url: item.size])
                    } else {
                        partial = Trash.move([item.url], sizes: [item.url: item.size])
                    }
                    result.removed += partial.removed
                    result.freed += partial.freed
                    result.failed += partial.failed
                }
            }
            let final = result
            await MainActor.run {
                self.lastResult = final
                self.isCleaning = false
                self.items = [:]
                self.analyzeAll()
            }
        }
    }
}
