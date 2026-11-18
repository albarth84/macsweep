import Foundation

struct AppInfo: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let executable: String
    /// App di sistema in /System/Applications: non eliminabili.
    let isSystem: Bool

    var isApple: Bool { bundleID.lowercased().hasPrefix("com.apple.") }
}

enum LeftoverReason {
    case appBundle, bundleID, name, launchItem

    var label: String {
        switch self {
        case .appBundle: "Applicazione"
        case .bundleID: "Bundle ID"
        case .name: "Nome app"
        case .launchItem: "Avvio automatico"
        }
    }
}

struct LeftoverItem: Identifiable {
    var id: String { url.path }
    let url: URL
    let location: String
    let reason: LeftoverReason
    let size: Int64
    /// Il percorso richiede privilegi di amministratore per essere rimosso.
    let needsAdmin: Bool
    var selected = true
}
