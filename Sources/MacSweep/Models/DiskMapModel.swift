import Foundation
import Observation

@MainActor
@Observable
final class DiskMapModel {
    var root: FileNode?
    var current: FileNode?
    var isScanning = false
    var scannedCount = 0
    var scanTarget: URL?
    var volume = VolumeInfo.current()
    var lastError: String?
    var revision = 0

    private var scanner: DiskScanner?

    func scan(_ url: URL) {
        scanner?.cancel()
        let scanner = DiskScanner()
        self.scanner = scanner
        scanTarget = url
        isScanning = true
        scannedCount = 0

        Task { @MainActor [weak self] in
            while true {
                guard let model = self, model.isScanning, model.scanner === scanner else { return }
                model.scannedCount = scanner.scannedCount
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        Task { @MainActor [weak self] in
            let tree = await Task.detached(priority: .userInitiated) { scanner.scan(url) }.value
            do {
                guard let self, self.scanner === scanner else { return }
                if !scanner.isCancelled {
                    self.root = tree
                    self.current = tree
                }
                self.scannedCount = scanner.scannedCount
                self.isScanning = false
                self.volume = VolumeInfo.current()
            }
        }
    }

    func cancelScan() {
        scanner?.cancel()
        isScanning = false
    }

    func navigate(to node: FileNode) {
        if node.canNavigate { current = node }
    }

    func goUp() {
        if let parent = current?.parent { current = parent }
    }

    func trash(_ node: FileNode) {
        guard !node.isAggregate else { return }
        let result = Trash.move([node.url])
        if result.removed.isEmpty {
            lastError = result.failed.first.map { "\($0.url.lastPathComponent): \($0.reason)" }
            return
        }
        if current === node || current?.ancestry.contains(node) == true { current = node.parent }
        node.detach()
        // L'albero è fatto di classi non osservate: `revision` forza l'aggiornamento delle viste.
        revision += 1
        volume = VolumeInfo.current()
    }
}
