import Foundation

/// Nodo dell'albero prodotto dalla scansione del disco.
final class FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    /// Nodo sintetico che raggruppa i file piccoli di una cartella.
    let isAggregate: Bool
    var size: Int64
    var children: [FileNode] = []
    weak var parent: FileNode?

    init(url: URL, name: String? = nil, isDirectory: Bool, isAggregate: Bool = false, size: Int64 = 0) {
        self.url = url
        self.name = name ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent)
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
        self.size = size
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var canNavigate: Bool { isDirectory && !children.isEmpty }

    /// Percorso dalla radice a questo nodo (per il breadcrumb).
    var ancestry: [FileNode] {
        var result = [self]
        var current = parent
        while let node = current {
            result.insert(node, at: 0)
            current = node.parent
        }
        return result
    }

    /// Rimuove il nodo dall'albero aggiornando le dimensioni degli antenati.
    func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var current: FileNode? = parent
        while let node = current {
            node.size -= size
            current = node.parent
        }
        self.parent = nil
    }

    /// I file più grandi del sottoalbero (esclusi i nodi aggregati).
    func largestFiles(limit: Int) -> [FileNode] {
        var all: [FileNode] = []
        func walk(_ node: FileNode) {
            for child in node.children {
                if child.isDirectory { walk(child) } else if !child.isAggregate { all.append(child) }
            }
        }
        walk(self)
        return Array(all.sorted { $0.size > $1.size }.prefix(limit))
    }
}
