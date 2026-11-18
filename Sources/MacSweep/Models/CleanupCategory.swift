import Foundation

enum CleanupRisk: Int, Comparable {
    case safe, review, caution

    static func < (a: CleanupRisk, b: CleanupRisk) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: "Sicuro"
        case .review: "Da verificare"
        case .caution: "Attenzione"
        }
    }
}

enum CleanupSource {
    /// Ogni sottoelemento delle cartelle indicate diventa un elemento eliminabile.
    case contents([String])
    /// Ogni percorso esistente è un elemento; viene svuotato il contenuto, la cartella resta.
    case folders([String])
    /// File con certe estensioni dentro una cartella (non ricorsivo).
    case files(dir: String, extensions: [String])
    /// Cartelle con questo nome trovate ricorsivamente nella Home (es. node_modules).
    case search(name: String)
    /// Cartelle di cache Chromium/Electron dentro ~/Library/Application Support/*.
    case electronCaches
}

struct CleanupCategory: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let risk: CleanupRisk
    let source: CleanupSource
    /// true = eliminazione definitiva (solo per il Cestino).
    var permanent = false

    static let all: [CleanupCategory] = [
        CleanupCategory(
            id: "user-caches", title: "Cache utente",
            detail: "~/Library/Caches. Le app le ricreano. Chiudi le app aperte prima di pulire.",
            symbol: "internaldrive", risk: .safe,
            source: .contents(["~/Library/Caches"])),
        CleanupCategory(
            id: "logs", title: "Log e report di crash",
            detail: "~/Library/Logs e DiagnosticReports.",
            symbol: "doc.text", risk: .safe,
            source: .contents(["~/Library/Logs"])),
        CleanupCategory(
            id: "electron", title: "Cache app Electron/Chromium",
            detail: "Cache, Code Cache, GPUCache… di app come VS Code, Slack, Discord, Claude, Cursor.",
            symbol: "bolt.horizontal", risk: .safe,
            source: .electronCaches),

        // MARK: Intelligenza artificiale
        CleanupCategory(
            id: "ai-cache", title: "IA · cache, log e file temporanei",
            detail: "Cache e log di Claude, Claude Code, ChatGPT, Codex, Cursor, LM Studio. Non tocca impostazioni né credenziali.",
            symbol: "brain", risk: .safe,
            source: .folders([
                "~/Library/Caches/claude-cli-nodejs",
                "~/Library/Caches/com.anthropic.claudefordesktop",
                "~/Library/Caches/com.anthropic.claudefordesktop.ShipIt",
                "~/Library/Caches/com.openai.chat",
                "~/Library/Caches/com.openai.codex",
                "~/Library/Logs/Claude",
                "~/.cache/claude",
                "~/.claude/debug",
                "~/.claude/shell-snapshots",
                "~/.claude/paste-cache",
                "~/.claude/cache",
                "~/.claude/downloads",
                "~/.codex/log",
                "~/.codex/tmp",
                "~/.codex/cache",
                "~/.codex/shell_snapshots",
                "~/.lmstudio/server-logs",
                "~/.cache/outlines",
                "~/Library/Application Support/Claude/Crashpad",
                "~/Library/Application Support/Claude/sentry",
                "~/Library/Application Support/Cursor/CachedExtensionVSIXs",
                "~/Library/Application Support/Cursor/logs",
            ])),
        CleanupCategory(
            id: "ai-history", title: "IA · cronologia sessioni",
            detail: "Trascrizioni delle conversazioni e snapshot dei file modificati dagli agenti. Perderai la possibilità di riprendere le vecchie sessioni.",
            symbol: "clock.arrow.circlepath", risk: .review,
            source: .folders([
                "~/.claude/projects",
                "~/.claude/file-history",
                "~/.codex/sessions",
                "~/.lmstudio/conversations",
            ])),
        CleanupCategory(
            id: "ai-models", title: "IA · modelli e runtime scaricati",
            detail: "Modelli locali (Ollama, LM Studio, Hugging Face, Whisper, PyTorch), VM di Claude, browser di Playwright. Verranno riscaricati se servono: possono essere molti GB.",
            symbol: "cpu", risk: .caution,
            source: .folders([
                "~/.ollama/models",
                "~/.lmstudio/models",
                "~/.cache/huggingface",
                "~/.cache/torch",
                "~/.cache/whisper",
                "~/.cache/lm-studio",
                "~/.cache/codex-runtimes",
                "~/Library/Application Support/Claude/vm_bundles",
                "~/Library/Caches/ms-playwright",
            ])),

        // MARK: Sviluppo
        CleanupCategory(
            id: "xcode-derived", title: "Xcode · DerivedData",
            detail: "Build intermedie di Xcode. Sicuro: vengono rigenerate.",
            symbol: "hammer", risk: .safe,
            source: .contents(["~/Library/Developer/Xcode/DerivedData"])),
        CleanupCategory(
            id: "xcode-support", title: "Xcode · supporto dispositivi e archivi",
            detail: "iOS/watchOS DeviceSupport e archivi delle build. Gli archivi servono per simbolicare i crash.",
            symbol: "iphone", risk: .review,
            source: .contents([
                "~/Library/Developer/Xcode/iOS DeviceSupport",
                "~/Library/Developer/Xcode/watchOS DeviceSupport",
                "~/Library/Developer/Xcode/Archives",
                "~/Library/Developer/CoreSimulator/Caches",
            ])),
        CleanupCategory(
            id: "package-caches", title: "Cache package manager",
            detail: "npm, yarn, pnpm, pip, uv, Gradle, Cargo, CocoaPods, Go.",
            symbol: "shippingbox", risk: .safe,
            source: .folders([
                "~/.npm/_cacache",
                "~/Library/Caches/Yarn",
                "~/Library/pnpm/store",
                "~/Library/Caches/pip",
                "~/.cache/pip",
                "~/.cache/uv",
                "~/.gradle/caches",
                "~/.cargo/registry/cache",
                "~/Library/Caches/CocoaPods",
                "~/Library/Caches/go-build",
                "~/.cache/prisma",
                "~/.cache/zig",
            ])),
        CleanupCategory(
            id: "node-modules", title: "Cartelle node_modules",
            detail: "Dipendenze JavaScript dei progetti nella Home. Si ripristinano con npm install.",
            symbol: "folder.badge.gearshape", risk: .review,
            source: .search(name: "node_modules")),

        // MARK: Altro
        CleanupCategory(
            id: "installers", title: "Installer nei Download",
            detail: "File .dmg, .pkg e .xip in ~/Downloads.",
            symbol: "arrow.down.circle", risk: .review,
            source: .files(dir: "~/Downloads", extensions: ["dmg", "pkg", "xip", "mpkg"])),
        CleanupCategory(
            id: "ios-backups", title: "Backup iPhone/iPad",
            detail: "Backup locali dei dispositivi iOS. Elimina solo quelli che non ti servono.",
            symbol: "externaldrive.badge.icloud", risk: .caution,
            source: .contents(["~/Library/Application Support/MobileSync/Backup"])),
        CleanupCategory(
            id: "trash", title: "Cestino",
            detail: "Elementi già nel Cestino. L'eliminazione è definitiva.",
            symbol: "trash", risk: .review,
            source: .contents(["~/.Trash"]), permanent: true),
    ]
}

struct CleanupItem: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    /// true = viene svuotato il contenuto ma la cartella rimane.
    let contentsOnly: Bool
    var selected = false

    var displayName: String {
        let home = NSHomeDirectory()
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
