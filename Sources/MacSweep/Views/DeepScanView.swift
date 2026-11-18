import SwiftUI
import AppKit
import QuickLook
import QuickLookThumbnailing

struct DeepScanView: View {
    @Bindable var model: DeepScanModel

    var body: some View {
        Group {
            switch model.phase {
            case .select: DriveSelectionView(model: model)
            case .scanning: ScanProgressView(model: model)
            case .results: ScanResultsView(model: model)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .onAppear { if model.drives.isEmpty { model.loadDrives() } }
    }
}

// MARK: - Selezione unità

private struct DriveSelectionView: View {
    @Bindable var model: DeepScanModel

    private let minimumSizes: [(String, Int64)] = [
        ("Tutti i file da 100 KB", 100_000), ("Da 1 MB (consigliato)", 1_000_000),
        ("Da 10 MB", 10_000_000), ("Da 100 MB", 100_000_000),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Scansione file",
                subtitle: "Scegli un'unità: MacSweep classifica ogni file per tipo e ti mostra cosa occupa spazio.",
                symbol: "magnifyingglass.circle", colors: Theme.green
            ) {
                Button { model.loadDrives() } label: { Label("Aggiorna", systemImage: "arrow.clockwise") }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Unità disponibili").font(.headline).foregroundStyle(.secondary)
                    ForEach(model.drives) { drive in
                        DriveCard(drive: drive, selected: model.customFolder == nil && model.selectedDriveID == drive.id)
                            .onTapGesture {
                                model.customFolder = nil
                                model.selectedDriveID = drive.id
                            }
                    }

                    if let folder = model.customFolder {
                        HStack(spacing: 14) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                                .resizable().frame(width: 44, height: 44)
                            VStack(alignment: .leading) {
                                Text(folder.lastPathComponent).font(.headline)
                                Text(folder.path).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Rimuovi") { model.customFolder = nil }
                        }
                        .card(highlighted: true)
                    }

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.prompt = "Scegli"
                        if panel.runModal() == .OK { model.customFolder = panel.url }
                    } label: {
                        Label("Scansiona una cartella specifica…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Divider()
            HStack(spacing: 16) {
                Picker("Elenca i file", selection: $model.minimumSize) {
                    ForEach(minimumSizes, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 300)
                .help("Tutti i file vengono contati nelle statistiche; nell'elenco finale compaiono solo quelli sopra questa soglia.")
                Spacer()
                Button {
                    model.start()
                } label: {
                    Label("Cerca file", systemImage: "magnifyingglass")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.gradient(Theme.green))
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedDrive == nil && model.customFolder == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }
}

private struct DriveCard: View {
    let drive: DriveInfo
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: drive.url.path))
                .resizable().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(drive.name).font(.headline)
                    Pill(text: drive.isRoot ? "Disco di avvio" : (drive.isInternal ? "Interno" : "Esterno"),
                         color: drive.isRoot ? .accentColor : (drive.isInternal ? .teal : .orange))
                    if !drive.format.isEmpty {
                        Text(drive.format).font(.caption).foregroundStyle(.secondary)
                    }
                }
                SegmentBar(segments: [
                    .init(value: drive.usedFraction, color: barColor),
                ], total: 1, height: 8)
                HStack {
                    Text("\(Fmt.bytes(drive.used)) usati").fontWeight(.medium)
                    Text("· \(Fmt.bytes(drive.available)) liberi su \(Fmt.bytes(drive.total))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
        }
        .contentShape(Rectangle())
        .card(highlighted: selected)
    }

    private var barColor: Color {
        drive.usedFraction > 0.9 ? .red : drive.usedFraction > 0.75 ? .orange : .accentColor
    }
}

// MARK: - Avanzamento

private struct ScanProgressView: View {
    @Bindable var model: DeepScanModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Scansione di \(model.scanTitle)",
                subtitle: model.isPaused ? "In pausa" : "Analisi in corso: puoi interrompere e vedere i risultati parziali.",
                symbol: "magnifyingglass.circle", colors: Theme.green
            ) {
                Button(model.isPaused ? "Riprendi" : "Pausa") { model.togglePause() }
                Button("Interrompi") { model.stop() }
                    .buttonStyle(.gradient(Theme.red))
            }

            ScrollView {
                VStack(spacing: 28) {
                    ZStack {
                        if let progress = model.progress {
                            RingGauge(progress: progress, lineWidth: 18, colors: Theme.green + [Color(hex: 0x0EA5E9)])
                        } else {
                            RingGauge(progress: 1, lineWidth: 18, colors: Theme.green.map { $0.opacity(0.35) })
                            ProgressView().controlSize(.large).offset(y: 46)
                        }
                        VStack(spacing: 4) {
                            if let progress = model.progress {
                                Text(progress, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText())
                            }
                            Text(Fmt.bytes(model.stats.bytes))
                                .font(.title3.weight(.semibold)).monospacedDigit()
                            Text("analizzati").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 230, height: 230)
                    .padding(.top, 8)

                    HStack(spacing: 36) {
                        stat("Tempo", Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                        stat("File trovati", model.stats.files.formatted())
                        if model.targetBytes > 0 {
                            stat("Dati sul disco", Fmt.bytes(model.targetBytes))
                        }
                    }

                    CategoryGrid(stats: model.stats)
                }
                .padding(24)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CategoryGrid: View {
    let stats: CategoryStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            ForEach(FileCategory.allCases) { category in
                HStack(spacing: 12) {
                    IconTile(symbol: category.symbol, colors: category.colors, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text("\(stats.count[category, default: 0].formatted()) file")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    Text(Fmt.bytes(stats.size[category, default: 0]))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                }
                .card(padding: 12)
            }
        }
        .animation(.default, value: stats.files)
    }
}

// MARK: - Risultati

private struct ScanResultsView: View {
    @Bindable var model: DeepScanModel
    @State private var previewURL: URL?
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Risultati: \(model.scanTitle)",
                subtitle: "\(model.stats.files.formatted()) file · \(Fmt.bytes(model.stats.bytes)) in \(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))"
                    + (model.wasStopped ? " · scansione interrotta" : ""),
                symbol: "checkmark.circle", colors: Theme.green
            ) {
                Button { model.newScan() } label: { Label("Nuova scansione", systemImage: "arrow.counterclockwise") }
            }

            SegmentBar(segments: FileCategory.allCases.map {
                .init(value: Double(model.stats.size[$0, default: 0]), color: $0.color)
            }, height: 10)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            HSplitView {
                categoryList.frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    fileTable
                }
                .frame(minWidth: 420)
                PreviewPanel(file: selectedSingle, onPreview: { previewURL = $0 })
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            }
            Divider()
            footer
        }
        .quickLookPreview($previewURL)
        .confirmationDialog(
            "Spostare nel Cestino \(model.selection.count) file (\(Fmt.bytes(model.selectedBytes)))?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino", role: .destructive) { model.trashSelected() }
        }
        .sheet(isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.lastResult = nil } })) {
            if let result = model.lastResult {
                ResultSheet(title: "File spostati nel Cestino", result: result) { model.lastResult = nil }
            }
        }
    }

    private var selectedSingle: FoundFile? {
        guard model.selection.count == 1, let id = model.selection.first else { return nil }
        return model.files.first { $0.id == id }
    }

    private var categoryList: some View {
        List(selection: Binding(
            get: { model.category?.rawValue ?? "all" },
            set: { model.category = $0.flatMap(FileCategory.init(rawValue:)) })
        ) {
            CategoryRow(title: "Tutti i file", symbol: "square.grid.2x2", colors: Theme.brand,
                        count: model.stats.files, size: model.stats.bytes)
                .tag("all")
            Section("Per tipo") {
                ForEach(FileCategory.allCases) { category in
                    CategoryRow(title: category.title, symbol: category.symbol, colors: category.colors,
                                count: model.stats.count[category, default: 0],
                                size: model.stats.size[category, default: 0])
                        .tag(category.rawValue)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Cerca per nome", text: $model.searchText).textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 260)
            Picker("", selection: $model.sizeFilter) {
                ForEach(SizeFilter.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().frame(width: 180)
            Picker("", selection: $model.ageFilter) {
                ForEach(AgeFilter.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().frame(width: 210)
            Spacer()
            Text("\(model.filtered.count.formatted()) elementi").font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var fileTable: some View {
        Table(model.filtered, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Nome", value: \.name) { file in
                HStack(spacing: 8) {
                    Image(systemName: file.category.symbol)
                        .foregroundStyle(file.category.color)
                        .frame(width: 16)
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 180, ideal: 280)
            TableColumn("Dimensione", value: \.size) { file in
                Text(Fmt.bytes(file.size)).monospacedDigit()
            }
            .width(min: 80, ideal: 90)
            TableColumn("Modificato", value: \.modified) { file in
                Text(file.modified == .distantPast ? "—" : file.modified.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Percorso", value: \.folder) { file in
                Text(file.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
        }
        .contextMenu(forSelectionType: FoundFile.ID.self) { ids in
            if let id = ids.first, let file = model.files.first(where: { $0.id == id }) {
                Button("Anteprima") { previewURL = file.url }
                Button("Mostra nel Finder") { Finder.reveal(file.url) }
                Divider()
                Button("Sposta nel Cestino…", role: .destructive) {
                    model.selection = ids
                    confirming = true
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let file = model.files.first(where: { $0.id == id }) { previewURL = file.url }
        }
        .overlay {
            if model.filtered.isEmpty {
                EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "Nessun file",
                               message: "Nessun file corrisponde ai filtri attuali.", colors: Theme.gray)
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.files.count >= FileTypeScanner.maxStoredFiles {
                Label("Elenco limitato ai primi \(FileTypeScanner.maxStoredFiles.formatted()) file", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.selection.isEmpty ? "Nessun file selezionato"
                 : "\(model.selection.count) selezionati · \(Fmt.bytes(model.selectedBytes))")
                .foregroundStyle(.secondary)
            Button("Sposta nel Cestino…") { confirming = true }
                .buttonStyle(.gradient(Theme.red))
                .disabled(model.selection.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct CategoryRow: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let count: Int
    let size: Int64

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, colors: colors, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text("\(count.formatted()) file").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.bytes(size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

/// Pannello laterale con miniatura e dettagli del file selezionato.
private struct PreviewPanel: View {
    let file: FoundFile?
    var onPreview: (URL) -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            if let file {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().scaledToFit()
                            .padding(30)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 10) {
                    Text(file.name).font(.headline).lineLimit(3)
                    Pill(text: file.category.title, color: file.category.color)
                    detail("Dimensione", Fmt.bytes(file.size))
                    detail("Modificato", file.modified == .distantPast ? "—"
                           : file.modified.formatted(date: .long, time: .shortened))
                    detail("Percorso", file.folder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Anteprima") { onPreview(file.url) }
                    Button("Mostra nel Finder") { Finder.reveal(file.url) }
                }
                Spacer()
            } else {
                EmptyStateView(symbol: "eye", title: "Anteprima",
                               message: "Seleziona un file per vederne la miniatura e i dettagli.", colors: Theme.gray)
            }
        }
        .padding(16)
        .task(id: file?.id) { await loadThumbnail() }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled).lineLimit(4)
        }
    }

    private func loadThumbnail() async {
        thumbnail = nil
        guard let file else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: file.url, size: CGSize(width: 400, height: 400), scale: 2, representationTypes: .thumbnail)
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = rep.nsImage
        }
    }
}
