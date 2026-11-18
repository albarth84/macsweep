import Foundation

enum CleanupScanner {
    private static let electronCacheNames = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GraphiteDawnCache", "GPUPersistentCache", "CachedData", "Service Worker/CacheStorage",
        "Service Worker/ScriptCache", "Crashpad/completed", "Crashpad/pending",
    ]

    static func items(for category: CleanupCategory) -> [CleanupItem] {
        let fm = FileManager.default
        var result: [CleanupItem] = []

        switch category.source {
        case .contents(let dirs):
            for dir in dirs {
                let url = URL(fileURLWithPath: dir.expandingTilde)
                let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
                for child in children where child.lastPathComponent != ".DS_Store" && child.lastPathComponent != ".localized" {
                    result.append(CleanupItem(url: child, size: FileSize.allocated(child), contentsOnly: false))
                }
            }

        case .folders(let paths):
            for path in paths {
                let expanded = path.expandingTilde
                guard FileSize.exists(expanded) else { continue }
                let url = URL(fileURLWithPath: expanded)
                result.append(CleanupItem(url: url, size: FileSize.allocated(url), contentsOnly: true))
            }

        case .files(let dir, let extensions):
            let url = URL(fileURLWithPath: dir.expandingTilde)
            let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
            for child in children where extensions.contains(child.pathExtension.lowercased()) {
                result.append(CleanupItem(url: child, size: FileSize.allocated(child), contentsOnly: false))
            }

        case .search(let name):
            for url in findFolders(named: name) {
                result.append(CleanupItem(url: url, size: FileSize.allocated(url), contentsOnly: false))
            }

        case .electronCaches:
            let support = URL(fileURLWithPath: "~/Library/Application Support".expandingTilde)
            let apps = (try? fm.contentsOfDirectory(at: support, includingPropertiesForKeys: nil, options: [])) ?? []
            for app in apps {
                for name in electronCacheNames {
                    let candidate = app.appendingPathComponent(name)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    result.append(CleanupItem(url: candidate, size: FileSize.allocated(candidate), contentsOnly: true))
                }
            }
        }

        return result.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    /// Cerca cartelle con un dato nome nella Home, saltando Library, cartelle nascoste e pacchetti.
    private static func findFolders(named name: String, maxDepth: Int = 8) -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
        else { return [] }

        var found: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if enumerator.level == 1 && url.lastPathComponent == "Library" {
                enumerator.skipDescendants()
                continue
            }
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  v.isDirectory == true, v.isSymbolicLink != true else { continue }
            if url.lastPathComponent == name {
                found.append(url)
                enumerator.skipDescendants() // niente node_modules annidati
            }
        }
        return found
    }
}
