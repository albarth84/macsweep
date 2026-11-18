import Foundation
import Observation

enum SizeFilter: Int64, CaseIterable, Identifiable {
    case any = 0, mb10 = 10_000_000, mb100 = 100_000_000, gb1 = 1_000_000_000
    var id: Int64 { rawValue }
    var title: String {
        switch self {
        case .any: "Qualsiasi dimensione"
        case .mb10: "Oltre 10 MB"
        case .mb100: "Oltre 100 MB"
        case .gb1: "Oltre 1 GB"
        }
    }
}

enum AgeFilter: Int, CaseIterable, Identifiable {
    case any = 0, months6 = 182, year1 = 365, years2 = 730
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .any: "Qualsiasi data"
        case .months6: "Non modificati da 6 mesi"
        case .year1: "Non modificati da 1 anno"
        case .years2: "Non modificati da 2 anni"
        }
    }
}

@MainActor
@Observable
final class DeepScanModel {
    enum Phase { case select, scanning, results }

    var phase: Phase = .select
    var drives: [DriveInfo] = []
    var selectedDriveID: String?
    var customFolder: URL?
    var minimumSize: Int64 = 1_000_000

    // Avanzamento
    var stats = CategoryStats()
    var startedAt: Date?
    var elapsed: TimeInterval = 0
    var isPaused = false
    var targetBytes: Int64 = 0
    var scanTitle = ""

    // Risultati
    var files: [FoundFile] = [] { didSet { refilter() } }
    var category: FileCategory? { didSet { refilter() } }
    var searchText = "" { didSet { refilter() } }
    var sizeFilter: SizeFilter = .any { didSet { refilter() } }
    var ageFilter: AgeFilter = .any { didSet { refilter() } }
    var sortOrder = [KeyPathComparator(\FoundFile.size, order: .reverse)] { didSet { refilter() } }
    private(set) var filtered: [FoundFile] = []
    var selection = Set<FoundFile.ID>()
    var lastResult: DeletionResult?
    var wasStopped = false

    private var scanner: FileTypeScanner?

    var selectedDrive: DriveInfo? { drives.first { $0.id == selectedDriveID } }

    var progress: Double? {
        guard targetBytes > 0 else { return nil }
        if phase == .results { return 1 }
        return min(0.99, Double(stats.bytes) / Double(targetBytes))
    }

    var selectedFiles: [FoundFile] {
        let ids = selection
        return files.filter { ids.contains($0.id) }
    }

    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func loadDrives() {
        drives = DriveInfo.mounted()
        if selectedDriveID == nil || selectedDrive == nil { selectedDriveID = drives.first?.id }
    }

    func start() {
        let root: URL
        if let customFolder {
            root = customFolder
            targetBytes = 0
            scanTitle = customFolder.lastPathComponent
        } else if let drive = selectedDrive {
            root = drive.url
            targetBytes = drive.used
            scanTitle = drive.name
        } else {
            return
        }

        let scanner = FileTypeScanner(minimumSize: minimumSize)
        self.scanner = scanner
        stats = CategoryStats()
        files = []
        selection = []
        category = nil
        isPaused = false
        wasStopped = false
        startedAt = Date()
        elapsed = 0
        phase = .scanning

        Task { @MainActor [weak self] in
            while true {
                guard let model = self, model.scanner === scanner, model.phase == .scanning else { return }
                model.stats = scanner.snapshot()
                if !model.isPaused, let start = model.startedAt { model.elapsed = Date().timeIntervalSince(start) }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        Task { @MainActor [weak self] in
            await Task.detached(priority: .userInitiated) { scanner.scan(root) }.value
            guard let self, self.scanner === scanner else { return }
            self.stats = scanner.snapshot()
            self.files = scanner.results()
            self.phase = .results
        }
    }

    func togglePause() {
        isPaused.toggle()
        scanner?.setPaused(isPaused)
        // Il tempo trascorso non deve crescere durante la pausa.
        if !isPaused { startedAt = Date().addingTimeInterval(-elapsed) }
    }

    /// Interrompe la scansione e mostra i risultati parziali.
    func stop() {
        wasStopped = true
        scanner?.cancel()
    }

    func newScan() {
        scanner?.cancel()
        scanner = nil
        phase = .select
        files = []
        selection = []
        loadDrives()
    }

    func trashSelected() {
        let chosen = selectedFiles
        guard !chosen.isEmpty else { return }
        let sizes = Dictionary(chosen.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        Task.detached(priority: .userInitiated) {
            let result = Trash.move(chosen.map(\.url), sizes: sizes)
            await MainActor.run {
                let removed = Set(result.removed.map(\.path))
                for file in chosen where removed.contains(file.url.path) {
                    self.stats.count[file.category, default: 1] -= 1
                    self.stats.size[file.category, default: file.size] -= file.size
                    self.stats.bytes -= file.size
                    self.stats.files -= 1
                }
                self.files.removeAll { removed.contains($0.url.path) }
                self.selection = []
                self.lastResult = result
            }
        }
    }

    func storedCount(_ category: FileCategory?) -> Int {
        guard let category else { return files.count }
        return files.reduce(0) { $0 + ($1.category == category ? 1 : 0) }
    }

    private func refilter() {
        var result = files
        if let category { result = result.filter { $0.category == category } }
        if sizeFilter != .any { result = result.filter { $0.size >= sizeFilter.rawValue } }
        if ageFilter != .any {
            let limit = Date().addingTimeInterval(-Double(ageFilter.rawValue) * 86_400)
            result = result.filter { $0.modified < limit }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        filtered = result.sorted(using: sortOrder)
    }
}
