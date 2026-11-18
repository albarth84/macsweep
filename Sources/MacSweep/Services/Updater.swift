import Foundation
import AppKit
import CryptoKit
import Security
import Observation

/// Versione semantica "MAJOR.MINOR.PATCH" (accetta il prefisso "v").
struct AppVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let clean = string.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = clean.split(separator: "-").first?.split(separator: ".").compactMap { Int($0) } ?? []
        guard parts.count == 3 else { return nil }
        (major, minor, patch) = (parts[0], parts[1], parts[2])
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

struct ReleaseInfo: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL
        let size: Int

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    var version: AppVersion? { AppVersion(tagName) }
    var zipAsset: Asset? { assets.first { $0.name.hasPrefix("MacSweep") && $0.name.hasSuffix(".zip") } }
    var checksumAsset: Asset? { assets.first { $0.name == "SHA256SUMS.txt" } }
}

/// Aggiornamenti tramite GitHub Releases.
///
/// 1. legge l'ultima release di `repository`;
/// 2. scarica `MacSweep-<versione>.zip` e ne verifica l'hash con `SHA256SUMS.txt`;
/// 3. estrae l'app, controlla bundle ID e versione;
/// 4. chiude MacSweep, sostituisce il bundle e lo riapre (script di shell separato).
@MainActor
@Observable
final class UpdateManager {
    static let shared = UpdateManager()
    static let repository = "albarth84/macsweep"
    static var repositoryURL: URL { URL(string: "https://github.com/\(repository)")! }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(Double)
        case installing
        case failed(String)
    }

    var state: State = .idle
    var latestRelease: ReleaseInfo?

    private static let autoCheckKey = "automaticUpdateChecks"
    private static let lastCheckKey = "lastUpdateCheck"

    var automaticChecks: Bool {
        get {
            access(keyPath: \.automaticChecks)
            return UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.automaticChecks) {
                UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey)
            }
        }
    }

    var lastCheck: Date? {
        get {
            access(keyPath: \.lastCheck)
            return UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        }
        set {
            withMutation(keyPath: \.lastCheck) { UserDefaults.standard.set(newValue, forKey: Self.lastCheckKey) }
        }
    }

    var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "sviluppo"
    }

    var currentVersion: AppVersion? { AppVersion(currentVersionString) }

    /// L'app è un bundle .app installato in una cartella scrivibile (non `swift run`).
    var canInstall: Bool {
        let path = Bundle.main.bundlePath
        return path.hasSuffix(".app")
            && FileManager.default.isWritableFile(atPath: (path as NSString).deletingLastPathComponent)
    }

    var availableRelease: ReleaseInfo? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// Controllo automatico, al massimo una volta al giorno.
    func checkAutomaticallyIfNeeded() async {
        guard automaticChecks else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 24 * 3600 {
            if let latestRelease, isNewer(latestRelease) { state = .available(latestRelease) }
            return
        }
        await check()
    }

    func check() async {
        if case .downloading = state { return }
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MacSweep-Updater", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                // Nessuna release pubblicata (o repository privato).
                lastCheck = Date()
                state = .upToDate
                return
            }
            guard status == 200 else { throw UpdateError.message("GitHub ha risposto con codice \(status).") }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release = try decoder.decode(ReleaseInfo.self, from: data)
            latestRelease = release
            lastCheck = Date()
            state = isNewer(release) ? .available(release) : .upToDate
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    private func isNewer(_ release: ReleaseInfo) -> Bool {
        guard let remote = release.version else { return false }
        guard let current = currentVersion else { return true } // build di sviluppo
        return remote > current
    }

    func downloadAndInstall() async {
        guard let release = availableRelease else { return }
        guard let asset = release.zipAsset else {
            state = .failed("La release \(release.tagName) non contiene il file .zip dell'app.")
            return
        }
        guard canInstall else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }

        state = .downloading(0)
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacSweep-Update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let zip = work.appendingPathComponent(asset.name)
            try await download(asset.browserDownloadURL, to: zip)

            if let checksums = release.checksumAsset {
                let (data, _) = try await URLSession.shared.data(from: checksums.browserDownloadURL)
                try verifyChecksum(of: zip, name: asset.name, checksums: String(decoding: data, as: UTF8.self))
            } else {
                throw UpdateError.message("Manca SHA256SUMS.txt nella release: aggiornamento annullato per sicurezza.")
            }

            state = .installing
            let extracted = work.appendingPathComponent("extracted")
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }),
                  let bundle = Bundle(url: newApp),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let newVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init),
                  newVersion == release.version
            else {
                throw UpdateError.message("Il pacchetto scaricato non è una versione valida di MacSweep.")
            }

            try verifySignature(of: newApp)
            try relaunch(replacingWith: newApp, scriptDirectory: work)
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    // MARK: - Implementazione

    private func download(_ url: URL, to destination: URL) async throws {
        let temporary: URL = try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                observation?.invalidate()
                if let error { return continuation.resume(throwing: error) }
                guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return continuation.resume(throwing: UpdateError.message("Download non riuscito."))
                }
                // Il file temporaneo viene cancellato al ritorno dall'handler: spostalo subito.
                let keep = location.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.moveItem(at: location, to: keep)
                    continuation.resume(returning: keep)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let value = progress.fractionCompleted
                Task { @MainActor in
                    if case .downloading = UpdateManager.shared.state { UpdateManager.shared.state = .downloading(value) }
                }
            }
            task.resume()
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private func verifyChecksum(of file: URL, name: String, checksums: String) throws {
        let expected = checksums.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts.last.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "*")) }) == name
            else { return nil }
            return String(parts[0]).lowercased()
        }.first
        guard let expected else { throw UpdateError.message("Checksum di \(name) non trovato.") }
        let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw UpdateError.message("Il file scaricato non corrisponde al checksum: aggiornamento annullato.")
        }
    }

    /// La nuova versione deve soddisfare il requisito di firma di quella installata
    /// (stesso bundle ID e stesso certificato). Così i permessi restano validi e un pacchetto
    /// firmato da altri viene rifiutato. Le build ad-hoc (requisito basato su cdhash) non hanno
    /// un'identità da confrontare: in quel caso si accetta l'aggiornamento.
    private func verifySignature(of newApp: URL) throws {
        var selfCode: SecCode?
        var staticSelf: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &staticSelf) == errSecSuccess, let staticSelf,
              SecCodeCopyDesignatedRequirement(staticSelf, [], &requirement) == errSecSuccess, let requirement
        else { return }

        var text: CFString?
        SecRequirementCopyString(requirement, [], &text)
        if let text = text as String?, text.contains("cdhash") { return }

        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw UpdateError.message("Impossibile leggere la firma della nuova versione.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else {
            throw UpdateError.message("La nuova versione non è firmata con lo stesso certificato: aggiornamento annullato.")
        }
    }

    /// Scrive uno script che attende la chiusura dell'app, sostituisce il bundle e la riapre.
    private func relaunch(replacingWith newApp: URL, scriptDirectory: URL) throws {
        let destination = Bundle.main.bundlePath
        let script = scriptDirectory.appendingPathComponent("install.sh")
        try """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        BACKUP="$DEST.previous"
        rm -rf "$BACKUP"
        if mv "$DEST" "$BACKUP" && /usr/bin/ditto "$NEW" "$DEST"; then
            rm -rf "$BACKUP"
        else
            rm -rf "$DEST"; mv "$BACKUP" "$DEST"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        /usr/bin/open "$DEST"
        """.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, destination]
        try process.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message("Estrazione dell'aggiornamento non riuscita.")
        }
    }

    private static func describe(_ error: Error) -> String {
        if case UpdateError.message(let text) = error { return text }
        if (error as? URLError)?.code == .notConnectedToInternet { return "Nessuna connessione a Internet." }
        return error.localizedDescription
    }

    enum UpdateError: Error {
        case message(String)
    }
}
