import Foundation

/// Cartelle di sistema in cui le app lasciano dati, preferenze, cache e servizi.
enum LibraryLocations {
    static let user: [(path: String, label: String)] = [
        ("~/Library/Application Support", "Application Support"),
        ("~/Library/Caches", "Cache"),
        ("~/Library/Preferences", "Preferenze"),
        ("~/Library/Preferences/ByHost", "Preferenze (ByHost)"),
        ("~/Library/Containers", "Container"),
        ("~/Library/Group Containers", "Group Container"),
        ("~/Library/Saved Application State", "Stato salvato"),
        ("~/Library/Logs", "Log"),
        ("~/Library/HTTPStorages", "HTTP Storage"),
        ("~/Library/WebKit", "WebKit"),
        ("~/Library/Cookies", "Cookie"),
        ("~/Library/LaunchAgents", "Avvio automatico"),
        ("~/Library/Application Scripts", "Script"),
    ]

    static let system: [(path: String, label: String)] = [
        ("/Library/Application Support", "Application Support (sistema)"),
        ("/Library/Caches", "Cache (sistema)"),
        ("/Library/Preferences", "Preferenze (sistema)"),
        ("/Library/LaunchAgents", "Avvio automatico (sistema)"),
        ("/Library/LaunchDaemons", "Servizi di sistema"),
        ("/Library/PrivilegedHelperTools", "Helper privilegiati"),
        ("/Library/Logs", "Log (sistema)"),
    ]

    /// Cartelle temporanee/cache per utente in /private/var/folders.
    static var temporary: [(path: String, label: String)] {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent()
        return [
            (tmp.appendingPathComponent("C").path, "Cache temporanea"),
            (tmp.appendingPathComponent("T").path, "File temporanei"),
        ]
    }

    static var all: [(path: String, label: String)] { user + system + temporary }

    static let launchFolders: Set<String> = [
        "~/Library/LaunchAgents".expandingTilde, "/Library/LaunchAgents", "/Library/LaunchDaemons",
    ]
}

/// Decide se il nome di un file/cartella si riferisce a una certa app.
struct AppMatcher {
    let bundleID: String
    let names: Set<String>

    private static let separators: Set<Character> = [".", "-", "_", " "]
    private static let strippedExtensions = [".plist", ".savedstate", ".binarycookies", ".log", ".app", ".helper"]
    private static let genericNames: Set<String> = [
        "app", "apps", "helper", "update", "updater", "data", "default", "support", "cache", "caches",
        "logs", "plugins", "settings", "config", "temp", "tmp", "shared", "common", "library",
    ]

    init(app: AppInfo) {
        bundleID = app.bundleID.lowercased()
        var names = Set<String>()
        for raw in [app.name, app.url.deletingPathExtension().lastPathComponent, app.executable] {
            let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard lower.count >= 3, !Self.genericNames.contains(lower) else { continue }
            names.insert(lower)
            names.insert(lower.replacingOccurrences(of: " ", with: ""))
        }
        self.names = names
    }

    func match(_ entryName: String) -> LeftoverReason? {
        let entry = entryName.lowercased()
        if !bundleID.isEmpty, Self.containsToken(entry, bundleID) { return .bundleID }
        var base = entry
        for ext in Self.strippedExtensions where base.hasSuffix(ext) {
            base = String(base.dropLast(ext.count))
        }
        return names.contains(base) ? .name : nil
    }

    /// `token` compare in `text` delimitato da separatori: evita che "com.foo" trovi "com.foobar".
    static func containsToken(_ text: String, _ token: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex
                || separators.contains(text[text.index(before: range.lowerBound)])
            let afterOK = range.upperBound == text.endIndex || separators.contains(text[range.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }
}

enum LeftoverFinder {
    static func find(for app: AppInfo) -> [LeftoverItem] {
        let fm = FileManager.default
        let matcher = AppMatcher(app: app)
        var items: [LeftoverItem] = []
        var seen = Set<String>()

        func add(_ url: URL, location: String, reason: LeftoverReason) {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path), SafetyGuard.isDeletable(url) else { return }
            seen.insert(path)
            let parent = url.deletingLastPathComponent().path
            items.append(LeftoverItem(
                url: url, location: location, reason: reason, size: FileSize.allocated(url),
                needsAdmin: !fm.isWritableFile(atPath: parent)))
        }

        if !app.isSystem {
            add(app.url, location: app.url.deletingLastPathComponent().path, reason: .appBundle)
        }

        for location in LibraryLocations.all {
            let dir = location.path.expandingTilde
            let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            let isLaunchFolder = LibraryLocations.launchFolders.contains(dir)
            for entry in entries {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                if let reason = matcher.match(entry) {
                    add(url, location: location.label, reason: isLaunchFolder ? .launchItem : reason)
                } else if isLaunchFolder, launchItem(url, pointsInto: app.url) {
                    add(url, location: location.label, reason: .launchItem)
                }
            }
        }

        return items.sorted {
            if ($0.reason == .appBundle) != ($1.reason == .appBundle) { return $0.reason == .appBundle }
            return $0.size > $1.size
        }
    }

    /// Un LaunchAgent/Daemon che avvia un eseguibile dentro il bundle dell'app.
    private static func launchItem(_ plist: URL, pointsInto appURL: URL) -> Bool {
        guard let program = LaunchItem.program(of: plist) else { return false }
        return program.hasPrefix(appURL.path + "/")
    }
}

enum LaunchItem {
    /// Percorso dell'eseguibile avviato da un plist di launchd.
    static func program(of plist: URL) -> String? {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        if let program = dict["Program"] as? String { return program }
        return (dict["ProgramArguments"] as? [String])?.first
    }
}
