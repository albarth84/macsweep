import SwiftUI
import AppKit

extension SystemDataKind {
    var color: Color {
        switch self {
        case .cleanable: Color(hex: 0x22C55E)
        case .appData: Color(hex: 0x3B82F6)
        case .system: Color(hex: 0x94A3B8)
        }
    }

    var symbol: String {
        switch self {
        case .cleanable: "sparkles"
        case .appData: "app.badge"
        case .system: "gearshape.2.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .cleanable: Theme.green
        case .appData: Theme.blue
        case .system: Theme.gray
        }
    }
}

struct SystemDataView: View {
    @Bindable var model: SystemDataModel
    /// Apre una cartella nella Mappa disco.
    var onExplore: (URL) -> Void
    @State var expanded: Set<String> = []
    @State private var pendingTrash: SystemDataItem?
    @State private var confirmingSnapshots = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: SidebarItem.systemData.title,
                subtitle: "Cosa c'è dentro la voce «Dati di sistema» di Impostazioni › Generali › Spazio.",
                symbol: SidebarItem.systemData.symbol, colors: SidebarItem.systemData.colors
            ) {
                Button { model.scan() } label: { Label("Analizza di nuovo", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanning)
            }
            content
        }
        .onAppear { if !model.hasScanned { model.scan() } }
        .confirmationDialog(
            "Spostare \"\(pendingTrash?.title ?? "")\" nel Cestino?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino (\(Fmt.bytes(pendingTrash?.size ?? 0)))", role: .destructive) {
                if let item = pendingTrash { model.trash(item) }
                pendingTrash = nil
            }
        } message: {
            Text(pendingTrash?.detail ?? "")
        }
        .confirmationDialog(
            "Eliminare gli snapshot locali di Time Machine?", isPresented: $confirmingSnapshots,
            titleVisibility: .visible
        ) {
            Button("Elimina snapshot", role: .destructive) { model.deleteSnapshots() }
        } message: {
            Text("I backup su disco esterno o di rete non vengono toccati. macOS chiederà la password di amministratore.")
        }
        .alert("Operazione non riuscita", isPresented: Binding(
            get: { model.snapshotError != nil || model.lastResult?.failed.isEmpty == false },
            set: { if !$0 { model.snapshotError = nil; model.lastResult = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(model.snapshotError ?? model.lastResult?.failed.first.map { "\($0.url.lastPathComponent): \($0.reason)" } ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && !model.hasScanned {
            VStack(spacing: 12) {
                ProgressView(value: model.progress).frame(width: 260)
                Text("Misuro le cartelle di sistema e delle app…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView { results }
            .overlay(alignment: .top) {
                if model.isScanning { ProgressView(value: model.progress).padding(.horizontal, 24) }
            }
        }
    }

    /// Contenuto dei risultati (fuori dallo ScrollView per poterlo anche renderizzare in anteprima).
    var results: some View {
        VStack(spacing: 14) {
            summary.card()
            if !model.snapshots.isEmpty || model.volume.purgeable > 1_000_000_000 {
                snapshotsCard.card()
            }
            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 62) }
                    groupRow(item)
                }
            }
            .card(padding: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Riepilogo

    private var summary: some View {
        let kinds = SystemDataKind.allCases
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.bytes(model.total))
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Stima: Impostazioni calcola la voce a modo suo e può differire di qualche GB.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            SegmentBar(segments: kinds.map {
                SegmentBar.Segment(value: Double(model.total(of: $0)), color: $0.color)
            }, height: 14)
            HStack(spacing: 18) {
                ForEach(kinds, id: \.self) { kind in
                    LegendDot(color: kind.color, title: kind.label, value: Fmt.bytes(model.total(of: kind)))
                }
            }
        }
    }

    private var snapshotsCard: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "clock.arrow.circlepath", colors: Theme.teal, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.snapshots.isEmpty
                     ? "Spazio eliminabile dal sistema"
                     : "Snapshot locali di Time Machine: \(model.snapshots.count)")
                    .font(.headline)
                Text("macOS libera \(Fmt.bytes(model.volume.purgeable)) da solo quando serve spazio: snapshot, cache di iCloud e contenuti già scaricati.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !model.snapshots.isEmpty {
                Button { confirmingSnapshots = true } label: {
                    if model.isDeletingSnapshots { ProgressView().controlSize(.small) } else { Text("Elimina snapshot") }
                }
                .disabled(model.isDeletingSnapshots)
            }
        }
    }

    // MARK: - Gruppi

    private func groupRow(_ item: SystemDataItem) -> some View {
        let isOpen = expanded.contains(item.id)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: item.url == nil ? "internaldrive.fill" : item.kind.symbol,
                             colors: item.kind.colors, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(item.title).font(.body.weight(.semibold))
                            Pill(text: item.kind.label, color: item.kind.color)
                        }
                        if !item.detail.isEmpty {
                            Text(item.detail).font(.callout).foregroundStyle(.secondary)
                                .lineLimit(isOpen ? nil : 1)
                                .fixedSize(horizontal: false, vertical: isOpen)
                        }
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Fmt.bytes(item.size)).font(.body.weight(.semibold).monospacedDigit())
                        sizeBar(item.size, of: model.items.first?.size ?? 1, color: item.kind.color)
                            .frame(width: 110)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .opacity(item.children.isEmpty && item.url == nil ? 0 : 1)
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 0) {
                    if let url = item.url {
                        HStack(spacing: 10) {
                            Spacer()
                            Button { Finder.reveal(url) } label: { Label("Mostra nel Finder", systemImage: "folder") }
                            Button { onExplore(url) } label: { Label("Esplora nella Mappa", systemImage: "chart.pie") }
                            if item.canTrash {
                                Button(role: .destructive) { pendingTrash = item } label: {
                                    Label("Sposta nel Cestino", systemImage: "trash")
                                }
                            }
                        }
                        .controlSize(.small)
                        .padding(.horizontal, 14).padding(.bottom, 8)
                    }
                    ForEach(item.children.prefix(25)) { child in
                        childRow(child, parent: item)
                    }
                    if item.children.count > 25 {
                        Text("e altri \(item.children.count - 25) elementi più piccoli")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 62).padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 8)
                .background(Color.primary.opacity(0.025))
            }
        }
    }

    private func childRow(_ child: SystemDataItem, parent: SystemDataItem) -> some View {
        HStack(spacing: 10) {
            Group {
                if let url = child.url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                } else {
                    Image(systemName: "doc")
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(child.title).lineLimit(1).truncationMode(.middle)
                    if child.kind != parent.kind { Pill(text: child.kind.label, color: child.kind.color) }
                    if child.isHighlight { Pill(text: "già inclusa sopra", color: .secondary) }
                }
                if !child.detail.isEmpty {
                    Text(child.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 10)
            Text(Fmt.bytes(child.size)).monospacedDigit().foregroundStyle(.secondary)
            sizeBar(child.size, of: parent.size, color: child.kind.color).frame(width: 70)
            HStack(spacing: 2) {
                if let url = child.url {
                    iconButton("folder", help: "Mostra nel Finder") { Finder.reveal(url) }
                    iconButton("chart.pie", help: "Esplora nella Mappa disco") { onExplore(url) }
                }
                iconButton("trash", help: "Sposta nel Cestino") { pendingTrash = child }
                    .opacity(child.canTrash ? 1 : 0)
                    .disabled(!child.canTrash)
            }
        }
        .padding(.leading, 62).padding(.trailing, 14).padding(.vertical, 5)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func sizeBar(_ value: Int64, of total: Int64, color: Color) -> some View {
        GeometryReader { geo in
            Capsule().fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: max(2, geo.size.width * min(1, Double(value) / Double(max(1, total)))))
                }
        }
        .frame(height: 5)
    }
}
