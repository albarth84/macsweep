import Foundation

/// Scansione ricorsiva del file system. Le sottocartelle di primo livello vengono
/// analizzate in parallelo; i file sotto `smallFileThreshold` vengono raggruppati
/// in un unico nodo per cartella per contenere l'uso di memoria.
final class DiskScanner: @unchecked Sendable {
    static let smallFileThreshold: Int64 = 1_000_000

    private let lock = NSLock()
    private var count = 0
    private var cancelled = false

    private let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Percorsi da non attraversare: volumi montati, firmlink duplicati, swap.
    private let skippedPaths: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/private/var/vm", "/net", "/home", "/cores",
    ]

    var scannedCount: Int { lock.withLock { count } }
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }

    func scan(_ root: URL) -> FileNode {
        scanDirectory(root, isRoot: true, parallel: true)
    }

    private func scanDirectory(_ url: URL, isRoot: Bool = false, parallel: Bool = false) -> FileNode {
        let node = FileNode(url: url, isDirectory: true)
        guard !isCancelled else { return node }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [])) ?? []

        var directories: [URL] = []
        var smallTotal: Int64 = 0
        var smallCount = 0

        for entry in entries {
            guard let v = try? entry.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            if skippedPaths.contains(entry.path) { continue }
            if v.isDirectory == true {
                if v.isVolume == true { continue } // non attraversare altri volumi
                directories.append(entry)
            } else {
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if size >= Self.smallFileThreshold {
                    let file = FileNode(url: entry, isDirectory: false, size: size)
                    file.parent = node
                    node.children.append(file)
                    node.size += size
                } else {
                    smallTotal += size
                    smallCount += 1
                }
            }
        }
        lock.withLock { count += entries.count }

        var subnodes = [FileNode?](repeating: nil, count: directories.count)
        if parallel && directories.count > 1 {
            let resultLock = NSLock()
            DispatchQueue.concurrentPerform(iterations: directories.count) { index in
                let child = scanDirectory(directories[index])
                resultLock.withLock { subnodes[index] = child }
            }
        } else {
            for (index, dir) in directories.enumerated() {
                subnodes[index] = scanDirectory(dir)
            }
        }

        for case let child? in subnodes {
            child.parent = node
            node.children.append(child)
            node.size += child.size
        }

        if smallCount > 0 && smallTotal > 0 {
            let aggregate = FileNode(
                url: url, name: "\(smallCount) file piccoli", isDirectory: false, isAggregate: true, size: smallTotal)
            aggregate.parent = node
            node.children.append(aggregate)
            node.size += smallTotal
        }

        node.children.sort { $0.size > $1.size }
        return node
    }
}
