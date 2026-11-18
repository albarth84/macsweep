import Foundation
import AppKit

enum OrphanConfidence: Int, Comparable {
    case low, medium, high

    static func < (a: OrphanConfidence, b: OrphanConfidence) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .high: "Alta"
        case .medium: "Media"
        case .low: "Bassa"
        }
    }
}

struct OrphanItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let identifier: String
    let location: String
    let confidence: OrphanConfidence
    let reason: String
    let size: Int64
    let needsAdmin: Bool
    var selected: Bool
}

/// Trova dati lasciati da app non più installate.
///
/// Logica:
/// - estrae un identificatore in stile bundle ID (com.vendor.app) dal nome di file/cartelle
///   nelle cartelle Library;
/// - se nessuna app installata (né LaunchServices) lo riconosce, è un candidato orfano;
/// - se un'altra app dello stesso sviluppatore è installata la confidenza scende a "media";
/// - i LaunchAgent/Daemon il cui eseguibile non esiste più sono orfani certi;
/// - cartelle senza bundle ID in Application Support vengono proposte con confidenza bassa.
enum OrphanFinder {
    private static let ignoredPrefixes = [
        "com.apple.", "apple.", "systemgroup.", "is.workflow.", "org.cups.", "org.swift.",
        "com.microsoft.autoupdate", "org.python.", "org.webkit.",
    ]

    /// Librerie incluse in molte app: i loro file non indicano un'app disinstallata specifica.
    private static let frameworkPrefixes = [
        "com.crashlytics", "com.plausiblelabs", "com.hackemist", "com.onevcat", "org.sparkle-project",
        "com.firebase", "com.segment", "com.google.firebase", "io.sentry", "com.bugsnag", "com.github.electron",
        "com.electron.", "org.chromium", "com.squirrel", "com.mixpanel", "com.amplitude", "io.realm",
    ]

    /// Cartelle dove vivono gli strumenti da riga di comando (Homebrew, npm, cargo…).
    private static let binaryDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "~/.local/bin", "~/.npm-global/bin", "~/.cargo/bin",
        "~/.bun/bin", "~/.deno/bin", "~/go/bin", "/opt/local/bin",
    ].map(\.expandingTilde)

    private static let genericComponents: Set<String> = [
        "cli", "app", "mac", "macos", "osx", "desktop", "helper", "agent", "daemon", "client", "plugin", "shared",
    ]

    /// Cartelle di Application Support create da macOS o da strumenti comuni, non da app.
    private static let knownSystemFolders: Set<String> = [
        "addressbook", "callhistorydb", "callhistorytransactions", "cloudDocs", "clouddocs", "crashreporter",
        "dock", "fileprovider", "icloud", "icdd", "knowledge", "mobilesync", "syncservices", "animoji",
        "applemediaservices", "accountsd", "networkserviceproxy", "diskimages", "caches", "contextstoreagent",
        "ttsasset", "familycircle", "facetime", "homeenergyd", "locationaccessstored", "quicklook",
        "replayd", "spotlight", "videoconference", "com.apple.sharedfilelist", "keychain", "assistant",
        "siri", "photos", "stocks", "weather", "maps", "music", "tv", "podcasts", "books", "news",
        "safari", "mail", "notes", "reminders", "calendars", "messages", "shortcuts", "freeform",
        "voicememos", "screen time", "screentime", "privacypreservingmeasurement", "dmd", "remindd",
        "mobile documents", "tipsd", "transparencyd", "watchlistd", "discrecording", "audiodata",
        "game center", "gamecenter", "appstore", "app store", "storeassetd", "calendardaemon", "akd",
        "authkit", "biome", "callservicesd", "cloudkit", "coreparsec", "ctkd", "fsck", "identityservicesd",
        "intelligenceplatform", "ipod", "mediaanalysis", "metadata", "passkit", "sharedfilelist",
        "studentd", "systemstatus", "trial", "tokens", "voicetrigger", "wallpaper", "xcpm",
        "coremlcache", "differentialprivacy", "cef", "firestore", "multimodal-models", "pyinstaller",
        "crashpad", "sentry", "electron", "node", "npm", "python", "java", "dotnet",
    ]

    static func find(installed: [AppInfo]) -> [OrphanItem] {
        let fm = FileManager.default
        let index = InstalledIndex(apps: installed, extraBundleIDs: pluginBundleIDs())
        var results: [OrphanItem] = []
        var seen = Set<String>()

        func add(_ url: URL, identifier: String, location: String, confidence: OrphanConfidence, reason: String) {
            guard !seen.contains(url.path), SafetyGuard.isDeletable(url) else { return }
            seen.insert(url.path)
            results.append(OrphanItem(
                url: url, identifier: identifier, location: location, confidence: confidence, reason: reason,
                size: FileSize.allocated(url),
                needsAdmin: !fm.isWritableFile(atPath: url.deletingLastPathComponent().path),
                selected: confidence == .high))
        }

        for location in LibraryLocations.user + LibraryLocations.system {
            let dir = location.path.expandingTilde
            let isLaunchFolder = LibraryLocations.launchFolders.contains(dir)
            let isAppSupport = dir == "~/Library/Application Support".expandingTilde
            let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []

            for entry in entries where !entry.hasPrefix(".") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)

                // 1. Servizi di avvio con eseguibile mancante: orfani certi.
                if isLaunchFolder {
                    if let program = LaunchItem.program(of: url), !program.isEmpty, !fm.fileExists(atPath: program) {
                        add(url, identifier: entry, location: location.label, confidence: .high,
                            reason: "Avvia \(program), che non esiste più")
                    }
                    continue
                }

                // 2. Nomi in stile bundle ID.
                if let identifier = bundleIdentifier(from: entry) {
                    if isIgnored(identifier) || index.isInstalled(identifier) || hasCommandLineTool(identifier) {
                        continue
                    }
                    if frameworkPrefixes.contains(where: { identifier.hasPrefix($0) }) {
                        add(url, identifier: identifier, location: location.label, confidence: .medium,
                            reason: "Dati di una libreria usata da più app")
                    } else if index.vendorInstalled(identifier) {
                        add(url, identifier: identifier, location: location.label, confidence: .medium,
                            reason: "App non trovata, ma è installato un altro prodotto dello stesso sviluppatore")
                    } else {
                        add(url, identifier: identifier, location: location.label, confidence: .high,
                            reason: "Nessuna app installata con questo identificatore")
                    }
                    continue
                }

                // 3. Cartelle con nome "umano" in Application Support.
                if isAppSupport {
                    let lower = entry.lowercased()
                    guard !knownSystemFolders.contains(lower), !index.matchesName(lower) else { continue }
                    add(url, identifier: entry, location: location.label, confidence: .low,
                        reason: "Nessuna app installata con questo nome: verifica prima di eliminare")
                }
            }
        }

        return results.sorted {
            $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.size > $1.size
        }
    }

    /// Bundle ID di plugin, pannelli delle preferenze ed estensioni installati fuori da /Applications.
    private static func pluginBundleIDs() -> [String] {
        let dirs = [
            "/Library/Internet Plug-Ins", "~/Library/Internet Plug-Ins", "/Library/PreferencePanes",
            "~/Library/PreferencePanes", "/Library/Audio/Plug-Ins/HAL", "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST3", "/Library/Application Support/Adobe/Plug-Ins",
            "/Library/Input Methods", "~/Library/Input Methods", "/Library/Screen Savers", "~/Library/Screen Savers",
            "/Library/SystemExtensions", "/Library/Extensions", "/Library/Frameworks",
        ].map(\.expandingTilde)
        var ids: [String] = []
        for dir in dirs {
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
                if let id = Bundle(path: "\(dir)/\(entry)")?.bundleIdentifier { ids.append(id) }
            }
        }
        return ids
    }

    private static func isIgnored(_ identifier: String) -> Bool {
        ignoredPrefixes.contains { identifier.hasPrefix($0) } || identifier.contains(".com.apple.")
    }

    /// "com.vercel.cli" -> esiste un comando `vercel` installato?
    private static func hasCommandLineTool(_ identifier: String) -> Bool {
        let candidates = identifier.split(separator: ".").dropFirst()
            .map(String.init)
            .filter { $0.count >= 3 && !genericComponents.contains($0) }
        return candidates.contains { name in
            binaryDirectories.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }
        }
    }

    /// "ABCDE12345.group.com.foo.bar.plist" -> "com.foo.bar"
    static func bundleIdentifier(from entry: String) -> String? {
        var name = entry.lowercased()
        for ext in [".plist", ".savedstate", ".binarycookies", ".lockfile", ".log"] where name.hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
        }
        // Preferenze ByHost: com.foo.bar.<UUID>
        if let range = name.range(of: #"\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
                                  options: .regularExpression) {
            name.removeSubrange(range)
        }
        // Team ID dei Group Container.
        if let range = name.range(of: #"^[0-9a-z]{10}\."#, options: .regularExpression),
           name.components(separatedBy: ".").count > 3 {
            name.removeSubrange(range)
        }
        for prefix in ["group.", "groups."] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }

        let parts = name.split(separator: ".")
        guard parts.count >= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }),
              let first = parts.first, first.count <= 6, first.allSatisfy(\.isLetter)
        else { return nil }
        return name
    }
}

/// Indice delle app installate per verifiche rapide.
private struct InstalledIndex {
    let bundleIDs: Set<String>
    let vendors: Set<String>
    let names: Set<String>
    let nameTokens: Set<String>

    init(apps: [AppInfo], extraBundleIDs: [String] = []) {
        bundleIDs = Set((apps.map(\.bundleID) + extraBundleIDs).map { $0.lowercased() }.filter { !$0.isEmpty })
        vendors = Set(bundleIDs.compactMap(Self.vendor))
        var names = Set<String>()
        var tokens = Set<String>()
        for app in apps {
            for raw in [app.name, app.executable, app.url.deletingPathExtension().lastPathComponent] {
                let lower = raw.lowercased()
                guard !lower.isEmpty else { continue }
                names.insert(lower)
                names.insert(lower.replacingOccurrences(of: " ", with: ""))
            }
            // "com.google.chrome" -> "google", "chrome"; "com.blackmagic-design.x" -> "blackmagic", "design".
            let words = app.bundleID.lowercased().split(whereSeparator: { ".-_".contains($0) })
                + app.name.lowercased().split(separator: " ")
            for word in words where word.count >= 3 && !Self.tlds.contains(String(word)) {
                tokens.insert(String(word))
            }
        }
        self.names = names
        self.nameTokens = tokens
    }

    private static let tlds: Set<String> = ["com", "org", "net", "app", "dev"]

    static func vendor(_ identifier: String) -> String? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".")
    }

    func isInstalled(_ identifier: String) -> Bool {
        if bundleIDs.contains(identifier) { return true }
        // Helper/estensioni: com.foo.app.helper appartiene a com.foo.app (e viceversa).
        for id in bundleIDs where identifier.hasPrefix(id + ".") || id.hasPrefix(identifier + ".") {
            return true
        }
        // App registrate in LaunchServices ma fuori da /Applications.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    func vendorInstalled(_ identifier: String) -> Bool {
        guard let vendor = Self.vendor(identifier) else { return false }
        return vendors.contains(vendor)
    }

    func matchesName(_ lower: String) -> Bool {
        if names.contains(lower) || names.contains(lower.replacingOccurrences(of: " ", with: "")) { return true }
        // "Cisco Spark" -> tutte le parole compaiono in bundle ID/nomi di app installate (Webex).
        let words = lower.split(whereSeparator: { " -_".contains($0) }).map(String.init).filter { $0.count >= 3 }
        if !words.isEmpty && words.allSatisfy(nameTokens.contains) { return true }
        if nameTokens.contains(lower) || nameTokens.contains(lower.replacingOccurrences(of: " ", with: "")) { return true }
        return names.contains { $0.count >= 4 && (lower.hasPrefix($0) || $0.hasPrefix(lower)) }
    }
}
