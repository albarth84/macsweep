import Foundation
import AppKit
import SwiftUI

enum WhatsAppMediaKind: String, CaseIterable, Identifiable {
    case photos, videos, audio, documents, stickers, thumbnails, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: "Foto"
        case .videos: "Video"
        case .audio: "Vocali e audio"
        case .documents: "Documenti"
        case .stickers: "Sticker"
        case .thumbnails: "Miniature"
        case .other: "Altro"
        }
    }

    var symbol: String {
        switch self {
        case .photos: "photo"
        case .videos: "film"
        case .audio: "waveform"
        case .documents: "doc.text"
        case .stickers: "face.smiling"
        case .thumbnails: "square.grid.3x3"
        case .other: "questionmark.square.dashed"
        }
    }

    var color: Color {
        switch self {
        case .photos: Color(hex: 0xEC4899)
        case .videos: Color(hex: 0x8B5CF6)
        case .audio: Color(hex: 0xF97316)
        case .documents: Color(hex: 0x3B82F6)
        case .stickers: Color(hex: 0xEAB308)
        case .thumbnails: Color(hex: 0x14B8A6)
        case .other: Color(hex: 0x94A3B8)
        }
    }

    static func from(extension ext: String) -> WhatsAppMediaKind {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff": .photos
        case "mp4", "mov", "m4v", "3gp", "avi", "mkv": .videos
        case "opus", "m4a", "aac", "mp3", "ogg", "amr", "wav", "caf": .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "csv", "zip", "rar", "7z",
             "pages", "numbers", "key", "rtf", "vcf", "apk", "dmg": .documents
        case "webp", "was", "tgs": .stickers
        case "thumb": .thumbnails
        default: .other
        }
    }
}

/// File di un certo tipo dentro la cartella media di una chat.
struct WhatsAppMediaGroup: Identifiable {
    var id: WhatsAppMediaKind { kind }
    let kind: WhatsAppMediaKind
    var usedFiles: [URL] = []
    var unusedFiles: [URL] = []
    var usedBytes: Int64 = 0
    var unusedBytes: Int64 = 0

    var bytes: Int64 { usedBytes + unusedBytes }
    var count: Int { usedFiles.count + unusedFiles.count }
}

struct WhatsAppChat: Identifiable {
    var id: String { folder.path }
    let folder: URL
    let jid: String
    let name: String
    let isStatus: Bool
    let isGroup: Bool
    var groups: [WhatsAppMediaGroup]
    var newestFile: Date?

    var bytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    var usedBytes: Int64 { groups.reduce(0) { $0 + $1.usedBytes } }
    var unusedBytes: Int64 { groups.reduce(0) { $0 + $1.unusedBytes } }
    var fileCount: Int { groups.reduce(0) { $0 + $1.count } }

    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first(where: \.isLetter) }
        return letters.isEmpty ? "#" : String(letters).uppercased()
    }
}

struct WhatsAppScanResult {
    var chats: [WhatsAppChat] = []
    var databaseFound = false
    var referencedCount = 0
}

/// Analizza i media di WhatsApp per Mac, chat per chat.
///
/// I file sono in `Message/Media/<jid>/…`; l'archivio `ChatStorage.sqlite` dice quali
/// sono ancora collegati a un messaggio. Il database viene copiato in una cartella
/// temporanea e letto in sola lettura: si leggono solo nomi delle chat e percorsi dei media,
/// mai il testo dei messaggi.
enum WhatsAppScanner {
    static let bundleID = "net.whatsapp.WhatsApp"
    static let container = URL(fileURLWithPath: "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared".expandingTilde)
    static var messageDirectory: URL { container.appendingPathComponent("Message") }
    static var mediaDirectory: URL { messageDirectory.appendingPathComponent("Media") }

    static var isAvailable: Bool { FileSize.exists(mediaDirectory.path) }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func quit() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }

    static func scan() -> WhatsAppScanResult {
        var result = WhatsAppScanResult()
        let (names, referenced, found) = readDatabase()
        result.databaseFound = found
        result.referencedCount = referenced.count

        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(
            at: mediaDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentModificationDateKey]
        let basePath = messageDirectory.path + "/"

        var chats = [WhatsAppChat?](repeating: nil, count: folders.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: folders.count) { index in
            let folder = folders[index]
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return }
            var groups: [WhatsAppMediaKind: WhatsAppMediaGroup] = [:]
            var newest: Date?
            let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                           errorHandler: { _, _ in true })
            while let file = enumerator?.nextObject() as? URL {
                guard let v = try? file.resourceValues(forKeys: Set(keys)), v.isDirectory != true else { continue }
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                let kind = WhatsAppMediaKind.from(extension: file.pathExtension)
                let relative = file.path.hasPrefix(basePath) ? String(file.path.dropFirst(basePath.count)) : file.path
                var group = groups[kind] ?? WhatsAppMediaGroup(kind: kind)
                // Senza database non si può sapere cosa è usato: tutto viene trattato come "usato" per prudenza.
                if found && !referenced.contains(relative) {
                    group.unusedFiles.append(file)
                    group.unusedBytes += size
                } else {
                    group.usedFiles.append(file)
                    group.usedBytes += size
                }
                groups[kind] = group
                if let date = v.contentModificationDate, date > (newest ?? .distantPast) { newest = date }
            }
            guard !groups.isEmpty else { return }

            let folderName = folder.lastPathComponent
            let isStatus = folderName.hasSuffix(".status")
            let jid = isStatus ? String(folderName.dropLast(".status".count)) : folderName
            let baseName = names[folderName] ?? names[jid] ?? prettyJID(jid)
            let chat = WhatsAppChat(
                folder: folder, jid: jid,
                name: isStatus ? "Stati di \(baseName)" : baseName,
                isStatus: isStatus, isGroup: jid.hasSuffix("@g.us"),
                groups: WhatsAppMediaKind.allCases.compactMap { groups[$0] }.filter { $0.count > 0 },
                newestFile: newest)
            lock.withLock { chats[index] = chat }
        }

        result.chats = chats.compactMap { $0 }.sorted { $0.bytes > $1.bytes }
        return result
    }

    private static func prettyJID(_ jid: String) -> String {
        let user = jid.split(separator: "@").first.map(String.init) ?? jid
        return jid.hasSuffix("@s.whatsapp.net") ? "+" + user : "Contatto \(user.suffix(4))"
    }

    /// Restituisce: nomi per JID, percorsi dei media referenziati, database trovato.
    private static func readDatabase() -> ([String: String], Set<String>, Bool) {
        let fm = FileManager.default
        let source = container.appendingPathComponent("ChatStorage.sqlite")
        guard fm.fileExists(atPath: source.path) else { return ([:], [], false) }

        let temp = fm.temporaryDirectory.appendingPathComponent("MacSweep-WhatsApp-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let file = container.appendingPathComponent("ChatStorage.sqlite\(suffix)")
                if fm.fileExists(atPath: file.path) {
                    try fm.copyItem(at: file, to: temp.appendingPathComponent("ChatStorage.sqlite\(suffix)"))
                }
            }
        } catch {
            return ([:], [], false)
        }
        guard let db = SQLiteReader(path: temp.appendingPathComponent("ChatStorage.sqlite").path) else {
            return ([:], [], false)
        }

        var names: [String: String] = [:]
        // Priorità più bassa per prima: i nomi più affidabili sovrascrivono.
        for row in db.rows("SELECT ZJID, ZPUSHNAME FROM ZWAPROFILEPUSHNAME") {
            if let jid = row[0], let name = row[1], !name.isEmpty { names[jid] = "~" + name }
        }
        for row in db.rows("SELECT ZMEMBERJID, COALESCE(NULLIF(ZCONTACTNAME, ''), ZFIRSTNAME) FROM ZWAGROUPMEMBER") {
            if let jid = row[0], let name = row[1], !name.isEmpty { names[jid] = name }
        }
        for row in db.rows("SELECT ZCONTACTJID, ZPARTNERNAME FROM ZWACHATSESSION") {
            if let jid = row[0], let name = row[1], !name.isEmpty { names[jid] = name }
        }

        var referenced = Set<String>()
        for row in db.rows("""
            SELECT ZMEDIALOCALPATH, ZXMPPTHUMBPATH, ZTHUMBNAILLOCALPATH FROM ZWAMEDIAITEM
            """) {
            for case let path? in row where !path.isEmpty {
                referenced.insert(path)
            }
        }
        return (names, referenced, true)
    }
}
