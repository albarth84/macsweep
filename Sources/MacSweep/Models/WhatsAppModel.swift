import Foundation
import Observation

enum WhatsAppMode: String, CaseIterable, Identifiable {
    case unusedOnly, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unusedOnly: "Solo media non usati"
        case .all: "Tutti i media"
        }
    }
}

@MainActor
@Observable
final class WhatsAppModel {
    var result = WhatsAppScanResult()
    var isScanning = false
    var hasScanned = false
    var isRemoving = false
    var mode: WhatsAppMode = .unusedOnly
    /// Chiavi "cartella|tipo" selezionate.
    var selection: Set<String> = []
    var expanded: Set<String> = []
    var lastResult: DeletionResult?
    var searchText = ""

    var statusChats: [WhatsAppChat] { filter(result.chats.filter(\.isStatus)) }
    var conversationChats: [WhatsAppChat] { filter(result.chats.filter { !$0.isStatus }) }

    var totalBytes: Int64 { result.chats.reduce(0) { $0 + $1.bytes } }
    var usedBytes: Int64 { result.chats.reduce(0) { $0 + $1.usedBytes } }
    var unusedBytes: Int64 { result.chats.reduce(0) { $0 + $1.unusedBytes } }
    var statusBytes: Int64 { result.chats.filter(\.isStatus).reduce(0) { $0 + bytes($1) } }

    private func filter(_ chats: [WhatsAppChat]) -> [WhatsAppChat] {
        let visible = chats.filter { bytes($0) > 0 }
        guard !searchText.isEmpty else { return visible }
        return visible.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: Dimensioni secondo la modalità

    func bytes(_ group: WhatsAppMediaGroup) -> Int64 {
        mode == .all ? group.bytes : group.unusedBytes
    }

    func count(_ group: WhatsAppMediaGroup) -> Int {
        mode == .all ? group.count : group.unusedFiles.count
    }

    func bytes(_ chat: WhatsAppChat) -> Int64 {
        chat.groups.reduce(0) { $0 + bytes($1) }
    }

    func visibleGroups(_ chat: WhatsAppChat) -> [WhatsAppMediaGroup] {
        chat.groups.filter { bytes($0) > 0 }
    }

    // MARK: Selezione

    private func key(_ chat: WhatsAppChat, _ kind: WhatsAppMediaKind) -> String { chat.id + "|" + kind.rawValue }

    func isSelected(_ chat: WhatsAppChat, _ kind: WhatsAppMediaKind) -> Bool {
        selection.contains(key(chat, kind))
    }

    func set(_ chat: WhatsAppChat, _ kind: WhatsAppMediaKind, _ on: Bool) {
        if on { selection.insert(key(chat, kind)) } else { selection.remove(key(chat, kind)) }
    }

    /// nil = selezione parziale.
    func chatSelectionState(_ chat: WhatsAppChat) -> Bool? {
        let groups = visibleGroups(chat)
        let selected = groups.filter { isSelected(chat, $0.kind) }.count
        if selected == 0 { return false }
        return selected == groups.count ? true : nil
    }

    func set(_ chat: WhatsAppChat, _ on: Bool) {
        for group in visibleGroups(chat) { set(chat, group.kind, on) }
    }

    func setAll(_ chats: [WhatsAppChat], _ on: Bool) {
        for chat in chats { set(chat, on) }
    }

    func selectedBytes(_ chat: WhatsAppChat) -> Int64 {
        visibleGroups(chat).filter { isSelected(chat, $0.kind) }.reduce(0) { $0 + bytes($1) }
    }

    var selectedBytes: Int64 { result.chats.reduce(0) { $0 + selectedBytes($1) } }

    var selectedFileCount: Int {
        result.chats.reduce(0) { total, chat in
            total + visibleGroups(chat).filter { isSelected(chat, $0.kind) }.reduce(0) { $0 + count($1) }
        }
    }

    var selectionIncludesUsedFiles: Bool {
        mode == .all && result.chats.contains { chat in
            chat.groups.contains { isSelected(chat, $0.kind) && $0.usedBytes > 0 }
        }
    }

    // MARK: Azioni

    func scan() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let result = WhatsAppScanner.scan()
            await MainActor.run {
                self.result = result
                self.isScanning = false
                self.hasScanned = true
                // Preseleziona la cache degli Stati: sono contenuti già scaduti.
                self.selection = []
                for chat in result.chats where chat.isStatus { self.set(chat, true) }
            }
        }
    }

    func remove() {
        let mode = self.mode
        var folders: [URL] = []
        var files: [URL] = []
        var sizes: [URL: Int64] = [:]

        for chat in result.chats {
            let chosen = visibleGroups(chat).filter { isSelected(chat, $0.kind) }
            guard !chosen.isEmpty else { continue }
            // Se si elimina tutto il contenuto della cartella, si sposta la cartella intera (più veloce).
            let everything = chosen.count == chat.groups.count
                && (mode == .all || chat.usedBytes == 0)
            if everything {
                folders.append(chat.folder)
                sizes[chat.folder] = chat.bytes
            } else {
                for group in chosen {
                    files += group.unusedFiles
                    if mode == .all { files += group.usedFiles }
                }
            }
        }
        guard !folders.isEmpty || !files.isEmpty else { return }

        isRemoving = true
        Task.detached(priority: .userInitiated) {
            var result = Trash.move(folders, sizes: sizes)
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: ".")
            let partial = Trash.moveIntoTrashFolder(files, folderName: "MacSweep WhatsApp \(stamp)") {
                FileSize.allocated($0)
            }
            result.removed += partial.removed
            result.freed += partial.freed
            result.failed += partial.failed
            let final = result
            await MainActor.run {
                self.isRemoving = false
                self.lastResult = final
                self.scan()
            }
        }
    }
}
