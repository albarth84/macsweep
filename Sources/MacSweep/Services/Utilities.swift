import Foundation
import AppKit

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

extension String {
    /// Espande `~` nella home dell'utente.
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
}

enum FileSize {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Spazio occupato su disco (allocato) da un file o da una cartella, ricorsivamente.
    static func allocated(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        while let item = enumerator?.nextObject() as? URL {
            guard let v = try? item.resourceValues(forKeys: Set(keys)),
                  v.isDirectory != true, v.isSymbolicLink != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

enum Permissions {
    /// Euristica: queste cartelle sono leggibili solo con "Accesso completo al disco".
    static func hasFullDiskAccess() -> Bool {
        let probes = [
            "~/Library/Safari",
            "~/Library/Containers/com.apple.stocks",
            "~/Library/Mail",
            "/Library/Application Support/com.apple.TCC",
        ]
        for probe in probes {
            let path = probe.expandingTilde
            guard FileSize.exists(path) else { continue }
            if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil { return true }
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Percorsi che MacSweep non deve mai eliminare, qualunque cosa succeda.
enum SafetyGuard {
    private static let home = NSHomeDirectory()

    private static let exactProtected: Set<String> = {
        var set: Set<String> = [
            "/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin",
            "/private", "/private/var", "/private/etc", "/opt", "/Volumes", "/cores",
        ]
        for sub in ["", "/Library", "/Documents", "/Desktop", "/Downloads", "/Pictures", "/Movies",
                    "/Music", "/Applications", "/Library/Application Support", "/Library/Caches",
                    "/Library/Preferences", "/Library/Containers", "/Library/Group Containers",
                    "/.Trash", "/Library/Mobile Documents", "/.ssh", "/.claude", "/.codex"] {
            set.insert(home + sub)
        }
        return set
    }()

    private static let protectedPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/private/var/db/"]

    static func isDeletable(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if exactProtected.contains(path) { return false }
        if protectedPrefixes.contains(where: { path.hasPrefix($0) }) { return false }
        if path.hasPrefix(home + "/.ssh/") { return false }
        // Non eliminare mai MacSweep stesso.
        if path.hasPrefix(Bundle.main.bundlePath) && Bundle.main.bundlePath.hasSuffix(".app") { return false }
        return true
    }
}

struct DeletionResult {
    var removed: [URL] = []
    var freed: Int64 = 0
    var failed: [(url: URL, reason: String)] = []
}

enum Trash {
    /// Sposta gli elementi nel Cestino. `sizes` serve solo per il riepilogo dello spazio liberato.
    static func move(_ urls: [URL], sizes: [URL: Int64] = [:]) -> DeletionResult {
        var result = DeletionResult()
        for url in urls {
            guard SafetyGuard.isDeletable(url) else {
                result.failed.append((url, "Percorso protetto"))
                continue
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.removed.append(url)
                result.freed += sizes[url] ?? 0
            } catch {
                result.failed.append((url, error.localizedDescription))
            }
        }
        return result
    }

    /// Sposta nel Cestino il *contenuto* di una cartella, lasciando la cartella stessa.
    static func moveContents(of dir: URL) -> DeletionResult {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
        var sizes: [URL: Int64] = [:]
        for child in children { sizes[child] = FileSize.allocated(child) }
        return move(children, sizes: sizes)
    }

    /// Eliminazione definitiva (usata solo per svuotare il Cestino).
    static func deletePermanently(_ urls: [URL], sizes: [URL: Int64] = [:]) -> DeletionResult {
        var result = DeletionResult()
        for url in urls {
            guard SafetyGuard.isDeletable(url) else {
                result.failed.append((url, "Percorso protetto"))
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                result.removed.append(url)
                result.freed += sizes[url] ?? 0
            } catch {
                result.failed.append((url, error.localizedDescription))
            }
        }
        return result
    }

    /// Sposta nel Cestino dell'utente file che richiedono privilegi di amministratore
    /// (es. /Library/LaunchDaemons). macOS chiede la password tramite il prompt di sistema.
    static func moveWithAdminPrivileges(_ urls: [URL]) -> DeletionResult {
        var result = DeletionResult()
        let safe = urls.filter(SafetyGuard.isDeletable)
        for url in urls where !safe.contains(url) { result.failed.append((url, "Percorso protetto")) }
        guard !safe.isEmpty else { return result }

        let trashDir = NSHomeDirectory() + "/.Trash"
        let stamp = Int(Date().timeIntervalSince1970)
        let commands = safe.map { url -> String in
            let dest = "\(trashDir)/\(url.lastPathComponent) \(stamp)"
            return "/bin/mv -f \(shellQuote(url.path)) \(shellQuote(dest))"
        }
        let shell = commands.joined(separator: " && ")
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Operazione annullata"
            result.failed.append(contentsOf: safe.map { ($0, message) })
        } else {
            result.removed = safe
        }
        return result
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum Finder {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct VolumeInfo {
    var total: Int64 = 0
    var available: Int64 = 0          // spazio libero "reale"
    var availableImportant: Int64 = 0 // include lo spazio purgeable

    var used: Int64 { max(0, total - availableImportant) }
    var purgeable: Int64 { max(0, availableImportant - available) }

    static func current(for url: URL = URL(fileURLWithPath: "/")) -> VolumeInfo {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else { return VolumeInfo() }
        let available = Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeInfo(
            total: Int64(v.volumeTotalCapacity ?? 0),
            available: available,
            availableImportant: max(available, v.volumeAvailableCapacityForImportantUsage ?? 0))
    }
}
