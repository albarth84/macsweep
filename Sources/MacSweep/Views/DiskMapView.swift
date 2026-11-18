import SwiftUI
import AppKit

struct DiskMapView: View {
    @Bindable var model: DiskMapModel
    @State private var hovered: FileNode?
    @State private var mode = 0
    @State private var pendingTrash: FileNode?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Mappa disco",
                subtitle: "Esplora le cartelle: ogni anello è un livello, l'ampiezza è lo spazio occupato.",
                symbol: SidebarItem.diskMap.symbol, colors: Theme.teal
            ) {
                scanButtons
            }
            VolumeBar(volume: model.volume)
                .card(padding: 14)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            content
        }
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

    private var scanButtons: some View {
        HStack(spacing: 8) {
            Menu {
                Button { model.scan(URL(fileURLWithPath: NSHomeDirectory())) } label: {
                    Label("Cartella Home", systemImage: "house")
                }
                Button { model.scan(URL(fileURLWithPath: "/")) } label: {
                    Label("Intero disco", systemImage: "internaldrive")
                }
                Divider()
                Button { chooseFolder() } label: { Label("Scegli cartella…", systemImage: "folder") }
            } label: {
                Label("Analizza", systemImage: "play.fill")
            }
            .menuStyle(.borderedButton)
            .fixedSize()
            .disabled(model.isScanning)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Scansione di \(model.scanTarget?.path ?? "")").font(.headline)
                Text("\(model.scannedCount.formatted()) elementi analizzati")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Button("Annulla") { model.cancelScan() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let current = model.current {
            VStack(spacing: 10) {
                HStack {
                    Button { model.goUp() } label: { Image(systemName: "chevron.left") }
                        .disabled(current.parent == nil)
                    Breadcrumb(node: current) { model.current = $0 }
                    Spacer()
                    Picker("", selection: $mode) {
                        Text("Mappa").tag(0)
                        Text("File più grandi").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                .padding(.horizontal, 24)

                if mode == 0 {
                    HStack(spacing: 14) {
                        SunburstView(
                            root: current, revision: model.revision, hovered: $hovered,
                            onSelect: { node in
                                if node.canNavigate { model.navigate(to: node) } else { Finder.reveal(node.url) }
                            },
                            onBack: { model.goUp() }
                        )
                        .padding(8)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                        .card(padding: 10)

                        NodeList(nodes: current.children, total: current.size, revision: model.revision,
                                 hovered: $hovered,
                                 onOpen: { model.navigate(to: $0) },
                                 onTrash: { pendingTrash = $0 })
                            .frame(minWidth: 320, idealWidth: 400, maxWidth: 480)
                            .card(padding: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                } else {
                    NodeList(nodes: current.largestFiles(limit: 200), total: current.size, revision: model.revision,
                             hovered: $hovered, showPath: true,
                             onOpen: { Finder.reveal($0.url) },
                             onTrash: { pendingTrash = $0 })
                        .card(padding: 0)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }
            }
        } else {
            VStack(spacing: 18) {
                EmptyStateView(
                    symbol: "chart.pie.fill", title: "Nessuna scansione",
                    message: "Analizza la Home, l'intero disco o una cartella per vedere dove finisce lo spazio.",
                    colors: Theme.teal)
                    .frame(maxHeight: 220)
                HStack(spacing: 10) {
                    Button { model.scan(URL(fileURLWithPath: NSHomeDirectory())) } label: {
                        Label("Analizza la Home", systemImage: "house.fill")
                    }
                    .buttonStyle(.gradient(Theme.teal))
                    Button { model.scan(URL(fileURLWithPath: "/")) } label: {
                        Label("Intero disco", systemImage: "internaldrive")
                    }
                    Button { chooseFolder() } label: { Label("Cartella…", systemImage: "folder") }
                }
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
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(item === node ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05),
                                    in: Capsule())
                        .foregroundStyle(item === node ? Color.accentColor : .primary)
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
        List(Array(nodes.enumerated()), id: \.element.id) { index, node in
            HStack(spacing: 10) {
                Image(nsImage: icon(for: node))
                    .resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(node.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Fmt.bytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if showPath {
                        Text(node.url.deletingLastPathComponent().path)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule().fill(color(for: node, index: index))
                                .frame(width: max(3, geo.size.width * fraction(node)))
                        }
                    }
                    .frame(height: 5)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .listRowBackground(node === hovered ? Color.accentColor.opacity(0.12) : Color.clear)
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
        .scrollContentBackground(.hidden)
        .id(revision)
    }

    private func color(for node: FileNode, index: Int) -> Color {
        if node.isAggregate { return .gray.opacity(0.5) }
        return showPath ? .accentColor : Color(Theme.chart[index % Theme.chart.count])
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive.fill").foregroundStyle(.secondary)
                Text("Macintosh HD").font(.headline)
                Spacer()
                Text("\(Fmt.bytes(volume.availableImportant)) disponibili su \(Fmt.bytes(volume.total))")
                    .foregroundStyle(.secondary)
            }
            SegmentBar(segments: [
                .init(value: Double(volume.used), color: .accentColor),
                .init(value: Double(volume.purgeable), color: .orange.opacity(0.8)),
            ], total: Double(max(1, volume.total)), height: 12)
            HStack(spacing: 18) {
                LegendDot(color: .accentColor, title: "Usato", value: Fmt.bytes(volume.used))
                LegendDot(color: .orange.opacity(0.8), title: "Eliminabile dal sistema", value: Fmt.bytes(volume.purgeable))
                LegendDot(color: .secondary.opacity(0.3), title: "Libero", value: Fmt.bytes(volume.available))
            }
        }
    }
}
