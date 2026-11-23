import Foundation
import Observation

@MainActor
@Observable
final class SystemDataModel {
    var items: [SystemDataItem] = []
    var snapshots: [String] = []
    var isScanning = false
    var hasScanned = false
    var progress = 0.0
    var volume = VolumeInfo.current()
    var lastResult: DeletionResult?
    var snapshotError: String?
    var isDeletingSnapshots = false

    var total: Int64 { items.reduce(0) { $0 + $1.size } }

    /// Totale per tipo. Le voci pulibili dentro un gruppo di altro tipo (es. il modello IA di Chrome
    /// dentro "Supporto applicazioni") contano come pulibili e vengono tolte dal gruppo.
    func total(of kind: SystemDataKind) -> Int64 {
        items.reduce(0) { sum, item in
            let cleanableInside = item.kind == .cleanable ? 0 : Self.cleanableSize(in: item)
            switch (item.kind == kind, kind == .cleanable) {
            case (true, true): return sum + item.size
            case (true, false): return sum + item.size - cleanableInside
            case (false, true): return sum + cleanableInside
            case (false, false): return sum
            }
        }
    }

    private static func cleanableSize(in item: SystemDataItem) -> Int64 {
        item.children.filter { $0.kind == .cleanable }.reduce(0) { $0 + $1.size }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        progress = 0
        Task.detached(priority: .userInitiated) {
            let found = SystemDataScanner.scan { done, count in
                let value = Double(done) / Double(max(1, count))
                Task { @MainActor in self.progress = max(self.progress, value) }
            }
            let snapshots = SystemDataScanner.localSnapshots()
            await MainActor.run {
                self.items = found
                self.snapshots = snapshots
                self.volume = VolumeInfo.current()
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    func trash(_ item: SystemDataItem) {
        guard item.canTrash, let url = item.url else { return }
        Task.detached(priority: .userInitiated) {
            let result = Trash.move([url], sizes: [url: item.size])
            await MainActor.run {
                self.lastResult = result
                if !result.removed.isEmpty { self.remove(item) }
                self.volume = VolumeInfo.current()
            }
        }
    }

    func deleteSnapshots() {
        isDeletingSnapshots = true
        Task.detached(priority: .userInitiated) {
            let error = SystemDataScanner.deleteLocalSnapshots()
            let remaining = SystemDataScanner.localSnapshots()
            await MainActor.run {
                self.snapshotError = error
                self.snapshots = remaining
                self.isDeletingSnapshots = false
                self.volume = VolumeInfo.current()
            }
        }
    }

    /// Toglie una voce eliminata e aggiorna i totali del gruppo che la conteneva.
    private func remove(_ removed: SystemDataItem) {
        for index in items.indices {
            if items[index].id == removed.id {
                items.remove(at: index)
                return
            }
            if let child = items[index].children.firstIndex(where: { $0.id == removed.id }) {
                items[index].children.remove(at: child)
                items[index].size = max(0, items[index].size - removed.size)
                // Le cartelle che contenevano la voce eliminata (es. "Claude" per vm_bundles) si riducono.
                for other in items[index].children.indices
                where removed.id.hasPrefix(items[index].children[other].id + "/") {
                    items[index].children[other].size -= removed.size
                }
                return
            }
        }
    }
}
