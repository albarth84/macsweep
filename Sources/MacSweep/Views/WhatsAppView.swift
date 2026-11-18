import SwiftUI
import AppKit

struct WhatsAppView: View {
    @Bindable var model: WhatsAppModel
    var onBack: () -> Void
    @State private var confirming = false
    @State private var whatsAppRunning = WhatsAppScanner.isRunning

    static let colors = [Color(hex: 0x25D366), Color(hex: 0x128C7E)]
    static let symbol = "bubble.left.and.bubble.right.fill"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Label("Pulizia", systemImage: "chevron.left") }
                    .buttonStyle(.link)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            PageHeader(
                title: "WhatsApp",
                subtitle: "Cache degli Stati e media delle chat, divisi per chat e per tipo.",
                symbol: Self.symbol, colors: Self.colors
            ) {
                Button { model.scan() } label: { Label("Analizza di nuovo", systemImage: "arrow.clockwise") }
                    .disabled(model.isScanning)
            }
            .padding(.top, -10)
            content
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            whatsAppRunning = WhatsAppScanner.isRunning
        }
        .confirmationDialog(
            "Spostare nel Cestino \(model.selectedFileCount.formatted()) file (\(Fmt.bytes(model.selectedBytes)))?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino", role: .destructive) { model.remove() }
        } message: {
            Text(model.selectionIncludesUsedFiles
                 ? "Attenzione: hai incluso media ancora collegati ai messaggi. Nelle chat compariranno come non disponibili e quelli vecchi potrebbero non essere più scaricabili."
                 : "Sono file che nessun messaggio usa più: le chat non cambiano. Restano recuperabili dal Cestino finché non lo svuoti.")
        }
        .sheet(isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.lastResult = nil } })) {
            if let result = model.lastResult {
                ResultSheet(title: "Pulizia WhatsApp completata", result: result) { model.lastResult = nil }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !WhatsAppScanner.isAvailable {
            EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "WhatsApp non trovato",
                           message: "Non c'è la cartella dati di WhatsApp per Mac su questo utente.", colors: Theme.gray)
        } else if model.isScanning {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Analisi dei media di WhatsApp…").font(.headline)
                Text("Lettura in sola lettura dell'archivio: solo nomi delle chat e percorsi dei file, mai i messaggi.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasScanned {
            VStack(spacing: 18) {
                EmptyStateView(
                    symbol: "bubble.left.and.bubble.right.fill", title: "Analizza WhatsApp",
                    message: "MacSweep confronta i file nella cartella di WhatsApp con l'archivio delle chat e ti mostra quali media nessun messaggio usa più.",
                    colors: Self.colors)
                    .frame(maxHeight: 240)
                Button { model.scan() } label: { Label("Analizza", systemImage: "play.fill") }
                    .buttonStyle(.gradient(Self.colors))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary
                        if whatsAppRunning { runningBanner }
                        if !model.result.databaseFound { databaseBanner }
                        controls
                        section(title: "Cache degli Stati", subtitle: "Stati dei contatti già scaduti (durano 24 ore).",
                                chats: model.statusChats)
                        section(title: "Chat", subtitle: "Media scaricati, chat per chat. Espandi per scegliere i tipi.",
                                chats: model.conversationChats)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                Divider()
                footer
            }
        }
    }

    // MARK: Riepilogo

    private var summary: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Media di WhatsApp su questo Mac").font(.callout).foregroundStyle(.secondary)
                Text(Fmt.bytes(model.totalBytes)).font(.system(size: 32, weight: .bold, design: .rounded))
                SegmentBar(segments: [
                    .init(value: Double(model.usedBytes), color: Self.colors[1]),
                    .init(value: Double(model.unusedBytes), color: Color(hex: 0xF59E0B)),
                ], height: 10)
                HStack(spacing: 16) {
                    LegendDot(color: Self.colors[1], title: "Usati dai messaggi", value: Fmt.bytes(model.usedBytes))
                    LegendDot(color: Color(hex: 0xF59E0B), title: "Non usati da nessun messaggio",
                              value: Fmt.bytes(model.unusedBytes))
                }
            }
            Spacer()
        }
        .card(padding: 18)
    }

    private var runningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("WhatsApp è aperto: chiudilo prima di eliminare i file.")
            Spacer()
            Button("Chiudi WhatsApp") { WhatsAppScanner.quit() }
        }
        .card(padding: 12)
    }

    private var databaseBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            Text("Archivio delle chat non leggibile: non è possibile distinguere i media usati. Tutti vengono considerati usati.")
                .font(.callout)
        }
        .card(padding: 12)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.mode) {
                ForEach(WhatsAppMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .help("\"Solo media non usati\" non modifica le chat. \"Tutti i media\" include anche file visibili nelle conversazioni.")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cerca chat", text: $model.searchText).textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 240)
            Spacer()
        }
    }

    // MARK: Sezioni

    @ViewBuilder
    private func section(title: String, subtitle: String, chats: [WhatsAppChat]) -> some View {
        let total = chats.reduce(Int64(0)) { $0 + model.bytes($1) }
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(chats.count) · \(Fmt.bytes(total))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button("Tutte") { model.setAll(chats, true) }.disabled(chats.isEmpty)
            Button("Nessuna") { model.setAll(chats, false) }.disabled(chats.isEmpty)
        }
        .padding(.top, 8)

        if chats.isEmpty {
            Text(model.mode == .unusedOnly ? "Nessun media non usato." : "Nessun media.")
                .foregroundStyle(.secondary).padding(.vertical, 6)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(chats) { chat in
                    ChatCard(model: model, chat: chat)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.bytes(model.selectedBytes))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text("\(model.selectedFileCount.formatted()) file selezionati")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRemoving { ProgressView().controlSize(.small) }
            Button { confirming = true } label: { Label("Sposta nel Cestino", systemImage: "trash") }
                .buttonStyle(.gradient(model.selectionIncludesUsedFiles ? Theme.red : Self.colors))
                .disabled(model.selectedFileCount == 0 || model.isRemoving || whatsAppRunning)
                .help(whatsAppRunning ? "Chiudi WhatsApp prima di procedere" : "")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .animation(.default, value: model.selectedBytes)
    }
}

private struct ChatCard: View {
    @Bindable var model: WhatsAppModel
    let chat: WhatsAppChat

    private var isExpanded: Bool { model.expanded.contains(chat.id) }

    var body: some View {
        let groups = model.visibleGroups(chat)
        let state = model.chatSelectionState(chat)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TriStateCheckbox(state: state) { model.set(chat, state != true) }
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(chat.name).font(.headline).lineLimit(1)
                        if chat.isGroup { Pill(text: "Gruppo", color: .teal) }
                    }
                    SegmentBar(segments: groups.map { .init(value: Double(model.bytes($0)), color: $0.kind.color) },
                               height: 6)
                        .frame(maxWidth: 320)
                    HStack(spacing: 8) {
                        Text("\(groups.reduce(0) { $0 + model.count($1) }.formatted()) file")
                        if let date = chat.newestFile {
                            Text("· ultimo \(date.formatted(date: .abbreviated, time: .omitted))")
                        }
                        if model.mode == .all && chat.usedBytes > 0 {
                            Text("· \(Fmt.bytes(chat.usedBytes)) usati nei messaggi").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.bytes(model.bytes(chat)))
                        .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    if state != false && state != true {
                        Text("\(Fmt.bytes(model.selectedBytes(chat))) selezionati")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button { Finder.reveal(chat.folder) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.borderless).help("Mostra nel Finder")
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { model.expanded.remove(chat.id) } else { model.expanded.insert(chat.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider().padding(.vertical, 10)
                VStack(spacing: 6) {
                    ForEach(groups) { group in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { model.isSelected(chat, group.kind) },
                                set: { model.set(chat, group.kind, $0) }))
                                .labelsHidden().toggleStyle(.checkbox)
                            Image(systemName: group.kind.symbol)
                                .foregroundStyle(group.kind.color)
                                .frame(width: 20)
                            Text(group.kind.title)
                            Text("\(model.count(group).formatted()) file").foregroundStyle(.secondary)
                            if model.mode == .all && group.usedBytes > 0 {
                                Pill(text: "\(group.usedFiles.count) nei messaggi", color: .orange)
                            }
                            Spacer()
                            Text(Fmt.bytes(model.bytes(group))).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                .padding(.leading, 64)
            }
        }
        .card(padding: 12, highlighted: state == true)
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.gradient(chat.isStatus ? Theme.orange : WhatsAppView.colors))
            .frame(width: 38, height: 38)
            .overlay {
                if chat.isStatus {
                    Image(systemName: "circle.dashed").font(.title3.weight(.semibold)).foregroundStyle(.white)
                } else if chat.isGroup {
                    Image(systemName: "person.3.fill").font(.caption).foregroundStyle(.white)
                } else {
                    Text(chat.initials).font(.callout.weight(.bold)).foregroundStyle(.white)
                }
            }
    }
}

/// Casella con stato misto (alcuni tipi selezionati).
struct TriStateCheckbox: View {
    let state: Bool?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == true ? "checkmark.square.fill" : state == nil ? "minus.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(state == false ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}
