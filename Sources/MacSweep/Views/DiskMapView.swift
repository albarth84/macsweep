import SwiftUI
import AppKit

struct DiskMapView: View {
    @Bindable var model: DiskMapModel
    @State private var hovered: FileNode?
    @State private var mode = 0
    @State private var pendingTrash: FileNode?

    var body: some View {
        VStack(spacing: 0) {
            VolumeBar(volume: model.volume).padding()
            Divider()
            controls.padding(.horizontal).padding(.vertical, 8)
            Divider()
            content
        }
        .navigationTitle("Mappa disco")
        .confirmationDialog(
            "Spostare \"\(pendingTrash?.name ?? "")\" nel Cestino?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino (\(Fmt.bytes(pendingTrash?.size ?? 0)))", role: .destructive) {
                if let node = pendingTrash { model.trash(node) }
                pendingTrash = nil
            }
        }
        .alert("Impossibile eliminare", isPresented: Binding(
            get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                model.scan(URL(fileURLWithPath: NSHomeDirectory()))
            } label: { Label("Home", systemImage: "house") }

            Button {
                model.scan(URL(fileURLWithPath: "/"))
            } label: { Label("Intero disco", systemImage: "internaldrive") }

            Button {
                chooseFolder()
            } label: { Label("Scegli cartella…", systemImage: "folder.badge.plus") }

            Spacer()

            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("\(model.scannedCount.formatted()) elementi").monospacedDigit().foregroundStyle(.secondary)
                Button("Annulla") { model.cancelScan() }
            } else if model.root != nil {
                Picker("", selection: $mode) {
                    Text("Mappa").tag(0)
                    Text("File più grandi").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
            }
        }
        .disabled(false)
    }

    @ViewBuilder
    private var content: some View {
        if let current = model.current {
            VStack(spacing: 0) {
                Breadcrumb(node: current) { model.current = $0 }
                    .padding(.horizontal).padding(.vertical, 6)
                Divider()
                if mode == 0 {
                    HSplitView {
                        SunburstView(
                            root: current, revision: model.revision, hovered: $hovered,
                            onSelect: { node in
                                if node.canNavigate { model.navigate(to: node) } else { Finder.reveal(node.url) }
                            },
                            onBack: { model.goUp() }
                        )
                        .padding()
                        .frame(minWidth: 380)

                        NodeList(nodes: current.children, total: current.size, revision: model.revision,
                                 hovered: $hovered,
                                 onOpen: { model.navigate(to: $0) },
                                 onTrash: { pendingTrash = $0 })
                            .frame(minWidth: 320, idealWidth: 380)
                    }
                } else {
                    NodeList(nodes: current.largestFiles(limit: 200), total: current.size, revision: model.revision,
                             hovered: $hovered, showPath: true,
                             onOpen: { Finder.reveal($0.url) },
                             onTrash: { pendingTrash = $0 })
                }
            }
        } else {
            ContentUnavailableView {
                Label(model.isScanning ? "Scansione in corso…" : "Nessuna scansione",
                      systemImage: model.isScanning ? "hourglass" : "chart.pie")
            } description: {
                Text(model.isScanning
                     ? (model.scanTarget?.path ?? "")
                     : "Analizza la Home, l'intero disco o una cartella per vedere dove finisce lo spazio.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analizza"
        if panel.runModal() == .OK, let url = panel.url { model.scan(url) }
    }
}

struct Breadcrumb: View {
    let node: FileNode
    var onSelect: (FileNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(node.ancestry) { item in
                    Button(item.name) { onSelect(item) }
                        .buttonStyle(.plain)
                        .foregroundStyle(item === node ? .primary : .secondary)
                    if item !== node {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

struct NodeList: View {
    let nodes: [FileNode]
    let total: Int64
    let revision: Int
    @Binding var hovered: FileNode?
    var showPath = false
    var onOpen: (FileNode) -> Void
    var onTrash: (FileNode) -> Void

    var body: some View {
        List(nodes) { node in
            HStack(spacing: 10) {
                Image(nsImage: icon(for: node))
                    .resizable().frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    if showPath {
                        Text(node.url.deletingLastPathComponent().path)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    GeometryReader { geo in
                        Capsule().fill(.tint.opacity(0.7))
                            .frame(width: geo.size.width * fraction(node))
                    }
                    .frame(height: 4)
                }
                Spacer()
                Text(Fmt.bytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .background(node === hovered ? Color.accentColor.opacity(0.12) : .clear)
            .onTapGesture(count: 2) { onOpen(node) }
            .contextMenu {
                if node.canNavigate { Button("Apri") { onOpen(node) } }
                Button("Mostra nel Finder") { Finder.reveal(node.url) }
                if !node.isAggregate {
                    Divider()
                    Button("Sposta nel Cestino…", role: .destructive) { onTrash(node) }
                }
            }
        }
        .id(revision)
    }

    private func fraction(_ node: FileNode) -> Double {
        total > 0 ? min(1, Double(node.size) / Double(total)) : 0
    }

    private func icon(for node: FileNode) -> NSImage {
        if node.isAggregate { return NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: node.url.path)
    }
}

struct VolumeBar: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Macintosh HD").font(.headline)
                Spacer()
                Text("\(Fmt.bytes(volume.availableImportant)) disponibili su \(Fmt.bytes(volume.total))")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let total = max(1, Double(volume.total))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.accentColor)
                        .frame(width: geo.size.width * Double(volume.used) / total)
                    Rectangle().fill(Color.orange.opacity(0.7))
                        .frame(width: geo.size.width * Double(volume.purgeable) / total)
                    Rectangle().fill(Color.secondary.opacity(0.2))
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 14)
            HStack(spacing: 16) {
                legend(.accentColor, "Usato", volume.used)
                legend(.orange.opacity(0.7), "Eliminabile dal sistema", volume.purgeable)
                legend(.secondary.opacity(0.3), "Libero", volume.available)
            }
            .font(.caption)
        }
    }

    private func legend(_ color: Color, _ title: String, _ value: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title): \(Fmt.bytes(value))").foregroundStyle(.secondary)
        }
    }
}
