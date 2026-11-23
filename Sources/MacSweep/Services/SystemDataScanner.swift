import Foundation

/// Che cosa si può fare con una voce di "Dati di sistema".
enum SystemDataKind: Int, CaseIterable, Comparable, Sendable {
    /// Si può eliminare: macOS o l'app la ricreano quando serve.
    case cleanable
    /// Dati delle app (profili, impostazioni, archivi): si eliminano dall'app o disinstallandola.
    case appData
    /// Gestita da macOS: non va toccata a mano.
    case system

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .cleanable: "Si può pulire"
        case .appData: "Dati delle app"
        case .system: "Gestito dal sistema"
        }
    }
}

struct SystemDataItem: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let kind: SystemDataKind
    /// Cartella su disco (nil per i volumi APFS, che non sono cartelle esplorabili).
    let url: URL?
    var size: Int64
    var children: [SystemDataItem] = []
    /// Voce già contenuta in un'altra dello stesso elenco: mostrata a parte ma non sommata.
    var isHighlight = false

    /// Solo voci pulibili nella cartella dell'utente e mai cartelle protette (es. ~/Library/Caches stessa:
    /// si eliminano i singoli elementi al suo interno).
    var canTrash: Bool {
        guard kind == .cleanable, let url else { return false }
        return url.path.hasPrefix(NSHomeDirectory() + "/") && SafetyGuard.isDeletable(url)
    }
}

/// Scompone la voce "Dati di sistema" delle Impostazioni: tutto ciò che macOS non attribuisce
/// ad App, Documenti, Foto, Mail, Messaggi, iCloud Drive o macOS stesso.
enum SystemDataScanner {
    private static let home = NSHomeDirectory()

    /// Cartelle di ~/Library che Impostazioni conta in altre categorie (o che non occupano spazio reale).
    private static let libraryExcluded: Set<String> = [
        "Application Support", "Containers", "Group Containers", "Caches", "Metadata", "Developer",
        "Mail", "Messages", "Mobile Documents", "CloudStorage", "Photos", "Trial",
    ]

    /// Voci riconosciute con una spiegazione dedicata. La chiave è il percorso (con `~`).
    private struct Known {
        let title: String
        let detail: String
        let kind: SystemDataKind
    }

    private static let known: [String: Known] = [
        "~/Library/Application Support/Claude/vm_bundles": Known(
            title: "Claude: immagini della macchina virtuale",
            detail: "Usate dalle funzioni che eseguono codice. Claude le riscarica quando servono.",
            kind: .cleanable),
        "~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel": Known(
            title: "Chrome: modello IA sul dispositivo",
            detail: "Gemini Nano per le funzioni IA di Chrome. Si riscarica se le usi.",
            kind: .cleanable),
        "~/Library/Application Support/Microsoft Edge/EdgeOnDeviceModel": Known(
            title: "Edge: modello IA sul dispositivo",
            detail: "Modello per le funzioni IA di Edge. Si riscarica se le usi.",
            kind: .cleanable),
        "~/Library/Application Support/Google/Chrome": Known(
            title: "Google Chrome",
            detail: "Profili di Chrome: cronologia, estensioni, cache dei siti. Si riduce da Chrome › Elimina dati di navigazione.",
            kind: .appData),
        "~/Library/Application Support/Claude": Known(
            title: "Claude",
            detail: "Dati dell'app Claude.",
            kind: .appData),
        "~/Library/Application Support/MobileSync": Known(
            title: "Backup di iPhone e iPad",
            detail: "Backup locali dei dispositivi. Si gestiscono dal Finder (seleziona il dispositivo › Gestisci backup).",
            kind: .appData),
        "~/Library/Application Support/CloudDocs": Known(
            title: "iCloud Drive (database)",
            detail: "Stato della sincronizzazione di iCloud Drive. Gestito da macOS.",
            kind: .system),
        "~/Library/Application Support/FileProvider": Known(
            title: "File Provider",
            detail: "Stato di sincronizzazione di OneDrive, Google Drive, Dropbox. Gestito da macOS.",
            kind: .system),
        "~/Library/Application Support/coreMLCache": Known(
            title: "Cache dei modelli Core ML",
            detail: "Modelli di machine learning compilati da macOS. Gestita dal sistema.",
            kind: .system),
        "~/Library/Caches": Known(
            title: "Cache dell'utente",
            detail: "File temporanei delle app: si ricreano quando servono. Le trovi anche in Pulizia.",
            kind: .cleanable),
        "~/Library/Metadata": Known(
            title: "Spotlight e Apple Intelligence",
            detail: "Indici di ricerca e analisi dei contenuti. macOS li ricostruisce da solo: non eliminarli a mano.",
            kind: .system),
        "~/Library/Developer": Known(
            title: "Strumenti per sviluppatori",
            detail: "Xcode, simulatori, cache di compilazione. Le parti eliminabili sono in Pulizia › Sviluppo.",
            kind: .appData),
        "~/Library/Containers": Known(
            title: "Container delle app",
            detail: "Dati delle app scaricate dall'App Store e di molte app Apple.",
            kind: .appData),
        "~/Library/Group Containers": Known(
            title: "Dati condivisi delle app",
            detail: "Dati condivisi tra un'app e le sue estensioni (es. Office, WhatsApp, Teams).",
            kind: .appData),
        "~/Library/Application Support": Known(
            title: "Supporto applicazioni (utente)",
            detail: "Dati delle app che non vengono dall'App Store: profili, database, modelli scaricati.",
            kind: .appData),
        "~/Library": Known(
            title: "Altro in Libreria",
            detail: "Preferenze, stato delle app, dati di servizi macOS.",
            kind: .system),
        "/Library": Known(
            title: "Libreria di sistema",
            detail: "Dati delle app installati per tutti gli utenti: driver, plug-in, contenuti scaricati.",
            kind: .appData),
        "/Library/Application Support": Known(
            title: "Supporto applicazioni (sistema)",
            detail: "Contenuti delle app per tutti gli utenti (es. librerie audio, componenti Adobe).",
            kind: .appData),
        "/Library/Caches": Known(
            title: "Cache di sistema",
            detail: "Cache condivise: si ricreano quando servono.",
            kind: .cleanable),
        "/private/var": Known(
            title: "File di sistema variabili",
            detail: "Temporanei, log e database di macOS. Gestiti dal sistema.",
            kind: .system),
        "/private/var/folders": Known(
            title: "File temporanei",
            detail: "Temporanei e cache per utente. macOS li ripulisce da solo, soprattutto al riavvio.",
            kind: .system),
        "/private/var/db": Known(
            title: "Database di sistema",
            detail: "Database interni di macOS (es. aggiornamenti, Spotlight, diagnostica).",
            kind: .system),
        "/private/var/log": Known(
            title: "Log di sistema",
            detail: "Registri di macOS. Si ruotano automaticamente.",
            kind: .system),
        "/opt": Known(
            title: "Strumenti da riga di comando (/opt)",
            detail: "Homebrew e altri strumenti installati da terminale. Si puliscono con `brew cleanup`.",
            kind: .appData),
        "/usr/local": Known(
            title: "Strumenti da riga di comando (/usr/local)",
            detail: "Programmi installati da terminale.",
            kind: .appData),
    ]

    private static func knownInfo(_ url: URL) -> Known? {
        let path = url.path
        let key = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        return known[key]
    }

    /// Analizza le cartelle principali. `progress` riceve il numero di cartelle misurate e il totale.
    static func scan(progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) -> [SystemDataItem] {
        let library = URL(fileURLWithPath: home).appendingPathComponent("Library")
        let otherLibrary = children(of: library).filter { !libraryExcluded.contains($0.lastPathComponent) }

        // (radice, figli da misurare uno per uno)
        let groups: [(URL, [URL])] = [
            library.appendingPathComponent("Application Support"),
            library.appendingPathComponent("Containers"),
            library.appendingPathComponent("Group Containers"),
            library.appendingPathComponent("Caches"),
            library.appendingPathComponent("Metadata"),
            library.appendingPathComponent("Developer"),
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/private/var"),
            URL(fileURLWithPath: "/opt"),
            URL(fileURLWithPath: "/usr/local"),
        ].map { url in
            var kids = children(of: url)
            // La memoria virtuale è sul volume VM: contata a parte.
            if url.path == "/private/var" { kids.removeAll { $0.lastPathComponent == "vm" } }
            return (url, kids)
        } + [(library, otherLibrary)]

        let jobs = groups.enumerated().flatMap { index, group in group.1.map { (index, $0) } }
        let tracker = HardLinkTracker()
        let lock = NSLock()
        var sizes = [Int64](repeating: 0, count: jobs.count)
        var done = 0
        DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
            let size = FileSize.allocated(jobs[i].1, tracker: tracker)
            let finished = lock.withLock {
                sizes[i] = size
                done += 1
                return done
            }
            progress(finished, jobs.count)
        }

        var items: [SystemDataItem] = []
        for (index, group) in groups.enumerated() {
            var kids: [SystemDataItem] = []
            for (i, job) in jobs.enumerated() where job.0 == index && sizes[i] > 0 {
                kids.append(item(for: job.1, size: sizes[i], parentKind: knownInfo(group.0)?.kind ?? .appData))
            }
            // Le voci note dentro una sottocartella (es. il modello IA di Chrome) vengono messe in evidenza.
            if group.0 != library { kids += highlights(inside: group.0, among: kids) }
            kids = ordered(kids)
            let total = kids.reduce(0) { $0 + $1.size } - kids.filter(\.isHighlight).reduce(0) { $0 + $1.size }
            guard total > 0 else { continue }
            let info = knownInfo(group.0)
            items.append(SystemDataItem(
                id: group.0.path, title: info?.title ?? group.0.lastPathComponent,
                detail: info?.detail ?? "", kind: info?.kind ?? .appData, url: group.0,
                size: total, children: kids))
        }
        items += apfsVolumes()
        return items.sorted { $0.size > $1.size }
    }

    /// Cartelle di ~/Library che appartengono a servizi di macOS (il resto è di solito di app di terze parti).
    private static let appleLibraryFolders: Set<String> = [
        "Biome", "DuetExpertCenter", "Daemon Containers", "IntelligencePlatform", "HTTPStorages", "WebKit",
        "Shortcuts", "Assistant", "Accounts", "Keychains", "Preferences", "Logs", "Saved Application State",
        "Autosave Information", "Calendars", "Cookies", "Suggestions", "Weather", "Sharing", "Safari",
        "Passes", "Reminders", "Translation", "PersonalizationPortrait", "Trial", "Spelling", "Fonts",
        "Keyboard Services", "LanguageModeling", "Containers", "News", "Stocks", "StatusKit", "FrontBoard",
        "Intents", "Finance", "ContainerManager", "CoreFollowUp", "Mobile Documents", "Sounds", "Staging",
    ]

    private static func item(for url: URL, size: Int64, parentKind: SystemDataKind) -> SystemDataItem {
        let info = knownInfo(url)
        var kind = info?.kind ?? parentKind
        let name = url.lastPathComponent
        if info == nil, url.deletingLastPathComponent().path == home + "/Library" {
            kind = appleLibraryFolders.contains(name) || name.hasPrefix("com.apple.") ? .system : .appData
        }
        return SystemDataItem(
            id: url.path, title: info?.title ?? displayName(url), detail: info?.detail ?? "",
            kind: kind, url: url, size: size)
    }

    /// Ordina per dimensione e mette ogni voce evidenziata subito sotto la cartella che la contiene.
    private static func ordered(_ kids: [SystemDataItem]) -> [SystemDataItem] {
        let highlights = kids.filter(\.isHighlight)
        var out: [SystemDataItem] = []
        for kid in kids.filter({ !$0.isHighlight }).sorted(by: { $0.size > $1.size }) {
            out.append(kid)
            out += highlights.filter { $0.id.hasPrefix(kid.id + "/") }.sorted { $0.size > $1.size }
        }
        out += highlights.filter { h in !out.contains { $0.id == h.id } }
        return out
    }

    /// Voci note più in profondità (es. `Claude/vm_bundles`): mostrate accanto alla cartella che le contiene.
    private static func highlights(inside root: URL, among kids: [SystemDataItem]) -> [SystemDataItem] {
        let rootPath = root.path
        var out: [SystemDataItem] = []
        for (key, info) in known where info.kind == .cleanable {
            let path = key.expandingTilde
            // Solo voci più profonde di un livello: i figli diretti sono già nell'elenco.
            guard path.hasPrefix(rootPath + "/"),
                  path.dropFirst(rootPath.count + 1).contains("/"),
                  !kids.contains(where: { $0.id == path }),
                  FileSize.exists(path) else { continue }
            // Misura con un tracker separato: lo spazio è già incluso nella cartella che la contiene.
            let size = FileSize.allocated(URL(fileURLWithPath: path))
            guard size > 0 else { continue }
            var item = SystemDataItem(id: path, title: info.title, detail: info.detail, kind: .cleanable,
                                      url: URL(fileURLWithPath: path), size: size)
            item.isHighlight = true
            out.append(item)
        }
        return out
    }

    private static func displayName(_ url: URL) -> String {
        // I container delle app hanno nomi tipo "com.microsoft.teams2": il nome visualizzato è più leggibile.
        var name = FileManager.default.displayName(atPath: url.path)
        if name.isEmpty { name = url.lastPathComponent }
        // Group Containers: "UBF8T346G9.Office" → "Office", "group.net.whatsapp…" → "net.whatsapp…".
        if url.deletingLastPathComponent().lastPathComponent == "Group Containers" {
            if name.hasPrefix("group.") { name.removeFirst("group.".count) }
            if let range = name.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) {
                name.removeSubrange(range)
            }
        }
        return name
    }

    private static func children(of url: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
    }

    // MARK: - Volumi APFS

    /// Preboot, Recovery e VM (swap): volumi nascosti dello stesso contenitore del disco di avvio.
    static func apfsVolumes() -> [SystemDataItem] {
        guard let info = plist(["info", "-plist", "/"]),
              let container = info["APFSContainerReference"] as? String,
              let list = plist(["apfs", "list", "-plist"]),
              let containers = list["Containers"] as? [[String: Any]],
              let boot = containers.first(where: { $0["ContainerReference"] as? String == container }),
              let volumes = boot["Volumes"] as? [[String: Any]]
        else { return [] }

        let descriptions: [String: (String, String)] = [
            "VM": ("Memoria virtuale (swap)",
                   "macOS sposta qui la memoria quando la RAM non basta. Si libera da sola, anche riavviando."),
            "Preboot": ("Avvio di macOS (Preboot)",
                        "File necessari all'avvio e agli aggiornamenti. Indispensabile."),
            "Recovery": ("Recupero di macOS",
                         "Sistema di ripristino per reinstallare o riparare macOS. Indispensabile."),
            "Update": ("Aggiornamenti in preparazione",
                       "File di aggiornamenti di macOS scaricati o in corso. Si liberano dopo l'installazione."),
        ]
        var out: [SystemDataItem] = []
        for volume in volumes {
            guard let role = (volume["Roles"] as? [String])?.first, let text = descriptions[role],
                  let size = (volume["CapacityInUse"] as? NSNumber)?.int64Value, size > 0 else { continue }
            out.append(SystemDataItem(id: "apfs:" + role, title: text.0, detail: text.1, kind: .system,
                                      url: nil, size: size))
        }
        return out
    }

    private static func plist(_ arguments: [String]) -> [String: Any]? {
        guard let data = run("/usr/sbin/diskutil", arguments) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    static func run(_ tool: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    // MARK: - Snapshot locali di Time Machine

    static func localSnapshots() -> [String] {
        guard let data = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("com.apple.") }
    }

    /// Elimina tutti gli snapshot locali del disco di avvio (chiede la password di amministratore).
    static func deleteLocalSnapshots() -> String? {
        let source = "do shell script \"/usr/bin/tmutil deletelocalsnapshots /\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return nil }
        return errorInfo[NSAppleScript.errorMessage] as? String ?? "Operazione annullata"
    }
}
