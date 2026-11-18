import SwiftUI
import AppKit

struct CleanupView: View {
    @Bindable var model: CleanupModel
    @Bindable var whatsApp: WhatsAppModel
    @State private var confirming = false
    @State private var showingWhatsApp = false

    private var groups: [(String, [CleanupCategory])] {
        let ai = model.categories.filter { $0.id.hasPrefix("ai-") }
        let dev = model.categories.filter { ["xcode-derived", "xcode-support", "package-caches", "node-modules"].contains($0.id) }
        let used = Set((ai + dev).map(\.id))
        let system = model.categories.filter { !used.contains($0.id) }
        return [("Sistema e app", system), ("Intelligenza artificiale", ai), ("Sviluppo", dev)]
    }

    var body: some View {
        if showingWhatsApp {
            WhatsAppView(model: whatsApp) { showingWhatsApp = false }
                .transition(.move(edge: .trailing))
        } else {
            categoriesPage
        }
    }

    private var categoriesPage: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Pulizia",
                subtitle: "Le categorie sicure sono già selezionate. Espandi per scegliere i singoli elementi.",
                symbol: SidebarItem.cleanup.symbol, colors: Theme.pink
            ) {
                Button { model.analyzeAll() } label: { Label("Analizza di nuovo", systemImage: "arrow.clockwise") }
                    .disabled(!model.analyzing.isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.0) { title, categories in
                        Text(title).font(.headline).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(categories) { category in
                            CategoryCard(model: model, category: category)
                        }
                    }
                    if WhatsAppScanner.isAvailable {
                        Text("Messaggistica").font(.headline).foregroundStyle(.secondary).padding(.top, 8)
                        WhatsAppCard(model: whatsApp) {
                            if !whatsApp.hasScanned && !whatsApp.isScanning { whatsApp.scan() }
                            withAnimation(.easeInOut(duration: 0.2)) { showingWhatsApp = true }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .onAppear { if !model.hasAnalyzed && model.analyzing.isEmpty { model.analyzeAll() } }
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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.bytes(model.selectedTotal))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text("\(model.selectedCount) elementi selezionati · lo spazio si libera svuotando il Cestino")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isCleaning { ProgressView().controlSize(.small) }
            Button { confirming = true } label: { Label("Pulisci selezionati", systemImage: "sparkles") }
                .buttonStyle(.gradient(Theme.pink))
                .disabled(model.selectedCount == 0 || model.isCleaning)
        }
        .animation(.default, value: model.selectedTotal)
    }
}

private struct CategoryCard: View {
    @Bindable var model: CleanupModel
    let category: CleanupCategory
    @State private var expanded = false

    private var tileColors: [Color] {
        switch category.risk {
        case .safe: category.id.hasPrefix("ai-") ? Theme.brand : Theme.teal
        case .review: Theme.orange
        case .caution: Theme.red
        }
    }

    var body: some View {
        let list = model.items[category.id, default: []]
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { model.isAllSelected(category.id) },
                    set: { model.setAll(category.id, selected: $0) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(list.isEmpty)
                IconTile(symbol: category.symbol, colors: tileColors, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(category.title).font(.headline)
                        RiskBadge(risk: category.risk)
                    }
                    Text(category.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if model.analyzing.contains(category.id) {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.bytes(model.total(category.id)))
                            .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text("\(list.count) elementi").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(list.isEmpty)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !list.isEmpty { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } }

            if expanded && !list.isEmpty {
                Divider().padding(.vertical, 10)
                LazyVStack(spacing: 6) {
                    ForEach(list) { item in
                        ItemRow(model: model, categoryID: category.id, item: item)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .card(padding: 14)
    }
}

/// Scheda WhatsApp nella pagina Pulizia: apre il dettaglio per chat.
private struct WhatsAppCard: View {
    let model: WhatsAppModel
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right.circle").opacity(0) // allinea con le caselle delle altre schede
                IconTile(symbol: WhatsAppView.symbol, colors: WhatsAppView.colors, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("WhatsApp").font(.headline)
                        Pill(text: "Scelta per chat", color: WhatsAppView.colors[1])
                    }
                    Text("Cache degli Stati e media delle chat, divisi per chat e per tipo. I media non più usati dai messaggi si eliminano senza toccare le conversazioni.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if model.isScanning {
                    ProgressView().controlSize(.small)
                } else if model.hasScanned {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.bytes(model.unusedBytes))
                            .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text("non usati · \(Fmt.bytes(model.selectedBytes)) selezionati")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Analizza").font(.callout.weight(.medium)).foregroundStyle(Color.accentColor)
                }
                Image(systemName: "chevron.right").foregroundStyle(.secondary).frame(width: 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(padding: 14)
    }
}

private struct ItemRow: View {
    @Bindable var model: CleanupModel
    let categoryID: String
    let item: CleanupItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.selected },
                set: { newValue in
                    if let i = model.items[categoryID]?.firstIndex(where: { $0.id == item.id }) {
                        model.items[categoryID]?[i].selected = newValue
                    }
                }))
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).lineLimit(1).truncationMode(.middle)
                if item.contentsOnly {
                    Text("svuota il contenuto, la cartella resta").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { Finder.reveal(item.url) } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.borderless)
                .help("Mostra nel Finder")
        }
        .font(.callout)
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
