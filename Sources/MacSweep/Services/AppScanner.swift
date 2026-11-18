import Foundation

enum AppScanner {
    static let userRoots = ["/Applications", "~/Applications"]
    static let systemRoots = ["/System/Applications"]

    /// Elenca le app installate. Scende di un livello nelle sottocartelle (es. /Applications/Utilities).
    static func installedApps(includeSystem: Bool = false) -> [AppInfo] {
        var roots = userRoots.map { ($0.expandingTilde, false) }
        if includeSystem { roots += systemRoots.map { ($0, true) } }

        var seen = Set<String>()
        var apps: [AppInfo] = []
        for (root, isSystem) in roots {
            for url in appBundles(in: URL(fileURLWithPath: root), depth: 2) {
                guard let info = read(url, isSystem: isSystem), !seen.contains(info.id) else { continue }
                seen.insert(info.id)
                apps.append(info)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func appBundles(in dir: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var result: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                result.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                result += appBundles(in: entry, depth: depth - 1)
            }
        }
        return result
    }

    static func read(_ url: URL, isSystem: Bool = false) -> AppInfo? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(
            url: url,
            name: name,
            bundleID: bundle.bundleIdentifier ?? "",
            version: (info["CFBundleShortVersionString"] as? String) ?? "",
            executable: (info["CFBundleExecutable"] as? String) ?? "",
            isSystem: isSystem || url.path.hasPrefix("/System/"))
    }
}
