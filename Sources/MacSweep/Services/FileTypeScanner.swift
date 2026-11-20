import Foundation

/// Scansione di un volume o di una cartella che classifica ogni file per tipo.
/// Le statistiche sono aggiornate in tempo reale; vengono conservati solo i file
/// sopra `minimumSize` (per contenere la memoria su dischi con milioni di file).
final class FileTypeScanner: @unchecked Sendable {
    static let maxStoredFiles = 400_000

    let minimumSize: Int64

    private let lock = NSLock()
    private var stats = CategoryStats()
    private var found: [FoundFile] = []
    private var cancelled = false
    private var paused = false
    private let hardLinks = HardLinkTracker()

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isVolumeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey, .linkCountKey,
    ]
    private static let keySet = Set(keys)

    /// Percorsi esclusi: volume di sistema sigillato, altri volumi, swap.
    private static let skippedPaths: Set<String> = [
        "/System", "/Volumes", "/dev", "/private/var/vm", "/net", "/home", "/cores", "/System/Volumes",
    ]

    init(minimumSize: Int64) {
        self.minimumSize = minimumSize
    }

    var isCancelled: Bool { lock.withLock { cancelled } }
    var isPaused: Bool { lock.withLock { paused } }
    func cancel() { lock.withLock { cancelled = true; paused = false } }
    func setPaused(_ value: Bool) { lock.withLock { paused = value } }

    func snapshot() -> CategoryStats { lock.withLock { stats } }
    func results() -> [FoundFile] { lock.withLock { found } }

    func scan(_ root: URL) {
        walkParallel(root, rootPath: root.path, depth: 0)
    }

    // MARK: - Implementazione

    /// I primi due livelli vengono suddivisi tra più thread, poi ogni ramo è sequenziale.
    private func walkParallel(_ dir: URL, rootPath: String, depth: Int) {
        guard !isCancelled else { return }
        if depth >= 2 {
            walk(dir, rootPath: rootPath)
            return
        }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: Self.keys, options: [])) ?? []
        let accumulator = Accumulator(scanner: self)
        var subdirs: [URL] = []
        for entry in entries {
            guard let v = try? entry.resourceValues(forKeys: Self.keySet), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if Self.skippedPaths.contains(entry.path) || (v.isVolume == true && entry.path != rootPath) { continue }
                if v.isPackage == true {
                    accumulator.record(entry, size: FileSize.allocated(entry, tracker: hardLinks), modified: v.contentModificationDate)
                } else {
                    subdirs.append(entry)
                }
            } else if hardLinks.shouldCount(entry, linkCount: v.linkCount) {
                accumulator.record(entry, size: Self.size(v), modified: v.contentModificationDate)
            }
        }
        accumulator.flush()
        DispatchQueue.concurrentPerform(iterations: subdirs.count) { index in
            walkParallel(subdirs[index], rootPath: rootPath, depth: depth + 1)
        }
    }

    private func walk(_ dir: URL, rootPath: String) {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: Self.keys, options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true })
        else { return }

        let accumulator = Accumulator(scanner: self)
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 256 == 0 {
                waitWhilePaused()
                if isCancelled { break }
            }
            guard let v = try? url.resourceValues(forKeys: Self.keySet), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if Self.skippedPaths.contains(url.path) || v.isVolume == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard v.isPackage == true else { continue }
                accumulator.record(url, size: FileSize.allocated(url, tracker: hardLinks), modified: v.contentModificationDate)
            } else if hardLinks.shouldCount(url, linkCount: v.linkCount) {
                accumulator.record(url, size: Self.size(v), modified: v.contentModificationDate)
            }
        }
        accumulator.flush()
    }

    private func waitWhilePaused() {
        while isPaused && !isCancelled { usleep(150_000) }
    }

    private static func size(_ v: URLResourceValues) -> Int64 {
        Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }

    fileprivate func merge(stats partial: CategoryStats, files: [(URL, Int64, Date, FileCategory)]) {
        lock.withLock {
            stats.merge(partial)
            let room = Self.maxStoredFiles - found.count
            guard room > 0 else { return }
            for (url, size, date, category) in files.prefix(room) {
                found.append(FoundFile(id: found.count, url: url, size: size, modified: date, category: category))
            }
        }
    }

    /// Accumula risultati per un singolo thread e li unisce a blocchi per ridurre la contesa sul lock.
    private final class Accumulator {
        unowned let scanner: FileTypeScanner
        var stats = CategoryStats()
        var files: [(URL, Int64, Date, FileCategory)] = []
        var cache: [String: FileCategory] = [:]

        init(scanner: FileTypeScanner) { self.scanner = scanner }

        func record(_ url: URL, size: Int64, modified: Date?) {
            let ext = url.pathExtension
            let category: FileCategory
            if let cached = cache[ext] {
                category = cached
            } else {
                category = FileCategory.classify(extension: ext)
                cache[ext] = category
            }
            stats.files += 1
            stats.bytes += size
            stats.count[category, default: 0] += 1
            stats.size[category, default: 0] += size
            if size >= scanner.minimumSize {
                files.append((url, size, modified ?? .distantPast, category))
            }
            if stats.files >= 400 { flush() }
        }

        func flush() {
            guard stats.files > 0 else { return }
            scanner.merge(stats: stats, files: files)
            stats = CategoryStats()
            files.removeAll(keepingCapacity: true)
        }
    }
}

struct DriveInfo: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let format: String
    let total: Int64
    let available: Int64
    let isInternal: Bool
    let isRemovable: Bool
    let isRoot: Bool

    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func mounted() -> [DriveInfo] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsRemovableKey,
            .volumeIsEjectableKey, .volumeLocalizedFormatDescriptionKey, .volumeIsRootFileSystemKey,
            .volumeIsLocalKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsLocal != false, v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let isRoot = v.volumeIsRootFileSystem == true || url.path == "/"
            let available = isRoot
                ? max(Int64(v.volumeAvailableCapacity ?? 0), v.volumeAvailableCapacityForImportantUsage ?? 0)
                : Int64(v.volumeAvailableCapacity ?? 0)
            return DriveInfo(
                url: url,
                name: v.volumeLocalizedName ?? url.lastPathComponent,
                format: v.volumeLocalizedFormatDescription ?? "",
                total: Int64(total),
                available: available,
                isInternal: v.volumeIsInternal ?? false,
                isRemovable: (v.volumeIsRemovable ?? false) || (v.volumeIsEjectable ?? false),
                isRoot: isRoot)
        }
        .sorted { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
    }
}
