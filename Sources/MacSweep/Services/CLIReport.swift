import Foundation

/// `MacSweep --report [nome app]`: stampa cosa verrebbe proposto, senza eliminare nulla.
enum CLIReport {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--scan-types"), args.count > flag + 1 {
            scanTypes(URL(fileURLWithPath: args[flag + 1].expandingTilde))
        }
        guard let flag = args.firstIndex(of: "--report") else { return }
        let appQuery = args.count > flag + 1 ? args[flag + 1] : nil

        print("== Pulizia ==")
        for category in CleanupCategory.all {
            let items = CleanupScanner.items(for: category)
            let total = items.reduce(0) { $0 + $1.size }
            print(String(format: "%-45@ %10@  (%d elementi)", category.title as NSString,
                         Fmt.bytes(total) as NSString, items.count))
        }

        print("\n== File orfani ==")
        let installed = AppScanner.installedApps(includeSystem: true)
        let orphans = OrphanFinder.find(installed: installed)
        for item in orphans.sorted(by: { $0.size > $1.size }).prefix(25) {
            print("[\(item.confidence.label)] \(Fmt.bytes(item.size))\t\(item.url.path)")
        }
        print("Totale: \(orphans.count) elementi, \(Fmt.bytes(orphans.reduce(0) { $0 + $1.size }))")

        if let appQuery {
            print("\n== File collegati a \"\(appQuery)\" ==")
            let apps = AppScanner.installedApps()
            if let app = apps.first(where: { $0.name.localizedCaseInsensitiveContains(appQuery) }) {
                for item in LeftoverFinder.find(for: app) {
                    print("[\(item.reason.label)] \(Fmt.bytes(item.size))\t\(item.url.path)\(item.needsAdmin ? "  (admin)" : "")")
                }
            } else {
                print("App non trovata")
            }
        }
        exit(0)
    }

    /// `MacSweep --scan-types <cartella>`: statistiche per tipo di file.
    private static func scanTypes(_ root: URL) {
        let start = Date()
        let scanner = FileTypeScanner(minimumSize: 1_000_000)
        scanner.scan(root)
        let stats = scanner.snapshot()
        print("\(stats.files) file, \(Fmt.bytes(stats.bytes)) in \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
        for category in FileCategory.allCases {
            print(String(format: "%-28@ %8d  %10@", category.title as NSString, stats.count[category, default: 0],
                         Fmt.bytes(stats.size[category, default: 0]) as NSString))
        }
        for file in scanner.results().sorted(by: { $0.size > $1.size }).prefix(5) {
            print("  \(Fmt.bytes(file.size))\t\(file.category.title)\t\(file.url.path)")
        }
        exit(0)
    }
}
