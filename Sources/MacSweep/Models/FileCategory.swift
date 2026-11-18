import SwiftUI
import UniformTypeIdentifiers

enum FileCategory: String, CaseIterable, Identifiable {
    case images, videos, audio, documents, archives, apps, code, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .images: "Immagini"
        case .videos: "Video"
        case .audio: "Audio"
        case .documents: "Documenti"
        case .archives: "Archivi, dischi e VM"
        case .apps: "Applicazioni"
        case .code: "Codice e dati"
        case .other: "Altro"
        }
    }

    var symbol: String {
        switch self {
        case .images: "photo"
        case .videos: "film"
        case .audio: "music.note"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .apps: "app.badge"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "questionmark.square.dashed"
        }
    }

    var colors: [Color] {
        switch self {
        case .images: [Color(hex: 0xF472B6), Color(hex: 0xEC4899)]
        case .videos: [Color(hex: 0xA855F7), Color(hex: 0x7C3AED)]
        case .audio: [Color(hex: 0xF97316), Color(hex: 0xEA580C)]
        case .documents: [Color(hex: 0x3B82F6), Color(hex: 0x2563EB)]
        case .archives: [Color(hex: 0xEAB308), Color(hex: 0xCA8A04)]
        case .apps: [Color(hex: 0x14B8A6), Color(hex: 0x0D9488)]
        case .code: [Color(hex: 0x22C55E), Color(hex: 0x16A34A)]
        case .other: Theme.gray
        }
    }

    var color: Color { colors[0] }

    private static let documentExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "odt", "ods", "odp", "epub", "md",
    ]
    private static let archiveExtensions: Set<String> = [
        "dmg", "iso", "pkg", "mpkg", "xip", "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "sparseimage",
        "sparsebundle", "vmdk", "qcow2", "vdi", "img", "pvm", "utm", "vmwarevm", "vhd", "vhdx", "hdd", "ova", "ovf",
    ]
    private static let codeExtensions: Set<String> = [
        "json", "xml", "yaml", "yml", "sqlite", "db", "sqlite3", "log", "csv", "plist", "o", "a", "dylib", "jar",
        "wasm", "safetensors", "gguf", "bin", "pt", "ckpt", "onnx", "mlmodel", "npz",
    ]

    /// Classifica un file dall'estensione usando i Uniform Type Identifiers.
    static func classify(extension ext: String) -> FileCategory {
        let ext = ext.lowercased()
        if ext.isEmpty { return .other }
        if ext == "app" { return .apps }
        if ext == "photoslibrary" { return .images }
        if ext == "bundle" { return .other }
        if documentExtensions.contains(ext) { return .documents }
        if archiveExtensions.contains(ext) { return .archives }
        if codeExtensions.contains(ext) { return .code }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) || type.conforms(to: .rawImage) { return .images }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) {
            return .videos
        }
        if type.conforms(to: .application) || type.conforms(to: .applicationBundle) { return .apps }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archives }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .database) {
            return .code
        }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .rtf) {
            return .documents
        }
        return .other
    }
}

struct FoundFile: Identifiable, Hashable {
    let id: Int
    let url: URL
    let size: Int64
    let modified: Date
    let category: FileCategory

    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }
}

struct CategoryStats {
    var files = 0
    var bytes: Int64 = 0
    var count: [FileCategory: Int] = [:]
    var size: [FileCategory: Int64] = [:]

    mutating func merge(_ other: CategoryStats) {
        files += other.files
        bytes += other.bytes
        for (key, value) in other.count { count[key, default: 0] += value }
        for (key, value) in other.size { size[key, default: 0] += value }
    }
}
