import SwiftUI

struct CleanupView: View {
    @Bindable var model: CleanupModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(model.categories) { category in
                    CategorySection(model: model, category: category)
                }
            }
            Divider()
            footer.padding()
        }
        .navigationTitle("Pulizia")
        .toolbar {
            Button {
                model.analyzeAll()
            } label: { Label("Analizza tutto", systemImage: "magnifyingglass") }
                .disabled(!model.analyzing.isEmpty)
        }
        .onAppear { if !model.hasAnalyzed { model.analyzeAll() } }
        .confirmationDialog(
            "Pulire \(model.selectedCount) elementi (\(Fmt.bytes(model.selectedTotal)))?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Pulisci", role: .destructive) { model.clean() }
        } message: {
            Text("Gli elementi vengono spostati nel Cestino (il contenuto del Cestino viene eliminato definitivamente). Chiudi le app interessate prima di procedere.")
        }
        .sheet(isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.lastResult = nil } })) {
            if let result = model.lastResult {
                ResultSheet(title: "Pulizia completata", result: result) { model.lastResult = nil }
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Selezionati: \(Fmt.bytes(model.selectedTotal))").font(.headline)
                Text("Lo spazio si libera definitivamente svuotando il Cestino.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isCleaning { ProgressView().controlSize(.small) }
            Button("Pulisci selezionati…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedCount == 0 || model.isCleaning)
        }
    }
}

private struct CategorySection: View {
    @Bindable var model: CleanupModel
    let category: CleanupCategory
    @State private var expanded = false

    var body: some View {
        let list = model.items[category.id, default: []]
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(list) { item in
                ItemRow(model: model, categoryID: category.id, item: item)
            }
            if list.isEmpty && !model.analyzing.contains(category.id) {
                Text("Niente da pulire").foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { model.isAllSelected(category.id) },
                    set: { model.setAll(category.id, selected: $0) }))
                    .labelsHidden()
                    .disabled(list.isEmpty)
                Image(systemName: category.symbol)
                    .frame(width: 22)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(category.title).font(.headline)
                        RiskBadge(risk: category.risk)
                    }
                    Text(category.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.analyzing.contains(category.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Text(Fmt.bytes(model.total(category.id))).monospacedDigit()
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct ItemRow: View {
    @Bindable var model: CleanupModel
    let categoryID: String
    let item: CleanupItem

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { item.selected },
                set: { newValue in
                    if let i = model.items[categoryID]?.firstIndex(where: { $0.id == item.id }) {
                        model.items[categoryID]?[i].selected = newValue
                    }
                })
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName).lineLimit(1).truncationMode(.middle)
                    if item.contentsOnly {
                        Text("svuota il contenuto").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { Finder.reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Mostra nel Finder")
        }
    }
}

struct RiskBadge: View {
    let risk: CleanupRisk

    var body: some View {
        Text(risk.label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch risk {
        case .safe: .green
        case .review: .orange
        case .caution: .red
        }
    }
}

struct ResultSheet: View {
    let title: String
    let result: DeletionResult
    var onAdminRetry: (([URL]) -> Void)? = nil
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            Text("\(result.removed.count) elementi rimossi · \(Fmt.bytes(result.freed)) liberati")
            if !result.failed.isEmpty {
                Text("Non rimossi (\(result.failed.count)):").font(.headline)
                List(result.failed, id: \.url) { failure in
                    VStack(alignment: .leading) {
                        Text(failure.url.path).lineLimit(1).truncationMode(.middle)
                        Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 160)
            }
            HStack {
                if let onAdminRetry, !result.failed.isEmpty {
                    Button("Riprova come amministratore") { onAdminRetry(result.failed.map(\.url)) }
                }
                Spacer()
                Button("Chiudi", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
