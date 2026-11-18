import SwiftUI
import AppKit

struct OrphansView: View {
    @Bindable var model: OrphansModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "File orfani",
                subtitle: "Preferenze, cache, container e servizi di avvio rimasti dopo la disinstallazione.",
                symbol: SidebarItem.orphans.symbol, colors: Theme.orange
            ) {
                Picker("Confidenza", selection: $model.minimumConfidence) {
                    Text("Alta").tag(OrphanConfidence.high)
                    Text("Media").tag(OrphanConfidence.medium)
                    Text("Tutte").tag(OrphanConfidence.low)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button { model.scan() } label: { Label("Cerca di nuovo", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanning)
            }
            content
                .card(padding: 0)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .onAppear { if !model.hasScanned && !model.isScanning { model.scan() } }
        .confirmationDialog(
            "Spostare nel Cestino \(model.selectedItems.count) elementi (\(Fmt.bytes(model.selectedTotal)))?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino", role: .destructive) { model.removeSelected() }
        } message: {
            Text("Controlla gli elementi a confidenza media o bassa: possono appartenere a strumenti installati fuori da /Applications (es. Homebrew).")
        }
        .sheet(isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.lastResult = nil } })) {
            if let result = model.lastResult {
                ResultSheet(
                    title: "Pulizia orfani completata", result: result,
                    onAdminRetry: { model.retryWithAdmin($0) },
                    onClose: { model.lastResult = nil })
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            ProgressView("Analisi delle cartelle Library…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleIndices.isEmpty {
            EmptyStateView(
                symbol: "checkmark.seal.fill", title: "Nessun file orfano",
                message: model.hasScanned ? "Non c'è niente da pulire con questo livello di confidenza." : "",
                colors: Theme.green)
        } else {
            VStack(spacing: 0) {
                selectAllBar
                Divider()
                List {
                    ForEach(model.visibleIndices, id: \.self) { index in
                        OrphanRow(item: $model.items[index])
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Casella "Seleziona tutto" in cima all'elenco: agisce sugli elementi visibili col filtro attuale.
    private var selectAllBar: some View {
        let visible = model.visibleIndices
        let selected = visible.filter { model.items[$0].selected }.count
        let state: Bool? = selected == 0 ? false : (selected == visible.count ? true : nil)
        let total = visible.reduce(Int64(0)) { $0 + model.items[$1].size }
        return HStack(spacing: 10) {
            TriStateCheckbox(state: state) { model.setAllVisible(state != true) }
            Text("Seleziona tutto").font(.headline)
            Text("\(visible.count) elementi · \(Fmt.bytes(total))")
                .foregroundStyle(.secondary)
            Spacer()
            if selected > 0 {
                Text("\(selected) selezionati · \(Fmt.bytes(model.selectedTotal))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.setAllVisible(state != true) }
    }

    private var footer: some View {
        HStack {
            Button("Seleziona tutto") { model.setAllVisible(true) }
            Button("Deseleziona") { model.setAllVisible(false) }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.bytes(model.selectedTotal)).font(.system(.title3, design: .rounded).weight(.bold))
                Text("\(model.selectedItems.count) selezionati").font(.caption).foregroundStyle(.secondary)
            }
            if model.isRemoving { ProgressView().controlSize(.small) }
            Button { confirming = true } label: { Label("Rimuovi", systemImage: "trash") }
                .buttonStyle(.gradient(Theme.orange))
                .disabled(model.selectedItems.isEmpty || model.isRemoving)
        }
    }
}

private struct OrphanRow: View {
    @Binding var item: OrphanItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.selected).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    ConfidenceBadge(confidence: item.confidence)
                    if item.needsAdmin {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("\(item.location) · \(item.reason)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { Finder.reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
        }
        .help(item.url.path)
    }
}

private struct ConfidenceBadge: View {
    let confidence: OrphanConfidence

    var body: some View {
        Text(confidence.label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .gray
        }
    }
}
