import SwiftUI
import AppKit

struct OrphansView: View {
    @Bindable var model: OrphansModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dati di app non più installate").font(.headline)
                    Text("Preferenze, cache, container e servizi di avvio rimasti dopo la disinstallazione.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Confidenza minima", selection: $model.minimumConfidence) {
                    Text("Alta").tag(OrphanConfidence.high)
                    Text("Media").tag(OrphanConfidence.medium)
                    Text("Tutte").tag(OrphanConfidence.low)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding()
            Divider()
            content
            Divider()
            footer.padding()
        }
        .navigationTitle("File orfani")
        .toolbar {
            Button { model.scan() } label: { Label("Cerca", systemImage: "magnifyingglass") }
                .disabled(model.isScanning)
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
            ContentUnavailableView(
                "Nessun file orfano", systemImage: "checkmark.seal",
                description: Text(model.hasScanned ? "Non c'è niente da pulire con questo livello di confidenza." : ""))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.visibleIndices, id: \.self) { index in
                    OrphanRow(item: $model.items[index])
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Seleziona tutto") { model.setAllVisible(true) }
            Button("Deseleziona") { model.setAllVisible(false) }
            Spacer()
            Text("Selezionati: \(Fmt.bytes(model.selectedTotal))").foregroundStyle(.secondary)
            if model.isRemoving { ProgressView().controlSize(.small) }
            Button("Rimuovi selezionati…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.selectedItems.isEmpty || model.isRemoving)
        }
    }
}

private struct OrphanRow: View {
    @Binding var item: OrphanItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.selected).labelsHidden()
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
