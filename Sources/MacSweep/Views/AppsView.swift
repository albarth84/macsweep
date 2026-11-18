import SwiftUI
import AppKit

struct AppsView: View {
    @Bindable var model: AppsModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Applicazioni",
                subtitle: "Scegli un'app: MacSweep trova preferenze, cache, container e servizi collegati.",
                symbol: SidebarItem.apps.symbol, colors: Theme.blue
            ) {
                Button { model.load() } label: { Label("Aggiorna", systemImage: "arrow.clockwise") }
            }
            HStack(spacing: 14) {
                appList
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
                    .card(padding: 0)
                detail
                    .frame(minWidth: 460, maxWidth: .infinity)
                    .card(padding: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onAppear { if model.apps.isEmpty { model.load() } }
        .sheet(isPresented: Binding(get: { model.lastResult != nil }, set: { if !$0 { model.lastResult = nil } })) {
            if let result = model.lastResult {
                ResultSheet(
                    title: "Rimozione completata", result: result,
                    onAdminRetry: { model.retryWithAdmin($0) },
                    onClose: { model.lastResult = nil })
            }
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cerca app", text: $model.searchText).textFieldStyle(.plain)
                }
                .font(.body)
                .padding(8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                Picker("Ordina", selection: $model.sortOrder) {
                    ForEach(AppsModel.SortOrder.allCases) { order in
                        Label(order.title, systemImage: order.symbol).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .help("Ordina per nome o per dimensione")
            }
            .padding(10)
            List(model.filteredApps, selection: Binding(get: { model.selectedID }, set: { model.select($0) })) { app in
                AppRow(app: app, size: model.sizes[app.id], largest: model.largestSize,
                       showBar: model.sortOrder == .size)
                    .tag(app.id)
            }
            .scrollContentBackground(.hidden)
            .overlay { if model.isLoading { ProgressView() } }
            Divider()
            HStack {
                Text("\(model.apps.count) app installate")
                Spacer()
                if model.sizes.count < model.apps.count && !model.apps.isEmpty {
                    ProgressView().controlSize(.mini)
                    Text("misura dimensioni…")
                }
            }
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            AppDetail(model: model, app: app)
        } else {
            EmptyStateView(
                symbol: "app.dashed", title: "Seleziona un'app",
                message: "MacSweep cercherà preferenze, cache, container, log e servizi di avvio collegati all'app.",
                colors: Theme.blue)
        }
    }
}

private struct AppDetail: View {
    @Bindable var model: AppsModel
    let app: AppInfo
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            header.padding()
            if model.isSelectedAppRunning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text("\(app.name) è in esecuzione: chiudila prima di rimuoverla.")
                    Spacer()
                    Button("Chiudi app") { model.quitSelectedApp() }
                }
                .padding(.horizontal).padding(.bottom, 8)
            }
            Divider()
            if model.isSearchingLeftovers {
                ProgressView("Ricerca dei file collegati…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($model.leftovers) { $item in
                        LeftoverRow(item: $item)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            Divider()
            footer.padding()
        }
        .confirmationDialog(
            "Spostare nel Cestino \(model.leftovers.filter(\.selected).count) elementi (\(Fmt.bytes(model.selectedTotal)))?",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino", role: .destructive) { model.removeSelected() }
        } message: {
            Text("Potrai recuperarli dal Cestino finché non lo svuoti. Gli elementi di sistema potrebbero richiedere la password di amministratore.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(app.name).font(.title2.bold())
                    if !app.version.isEmpty { Pill(text: app.version, color: .secondary) }
                }
                Text(app.bundleID).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text(app.url.path).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Mostra nel Finder") { Finder.reveal(app.url) }
        }
    }

    private var footer: some View {
        HStack {
            Button("Seleziona tutto") { model.setAll(true) }
            Button("Deseleziona") { model.setAll(false) }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.bytes(model.selectedTotal)).font(.system(.title3, design: .rounded).weight(.bold))
                Text("\(model.leftovers.count) elementi trovati").font(.caption).foregroundStyle(.secondary)
            }
            if model.isRemoving { ProgressView().controlSize(.small) }
            Button { confirming = true } label: { Label("Rimuovi", systemImage: "trash") }
                .buttonStyle(.gradient(Theme.red))
                .disabled(model.selectedTotal == 0 && model.leftovers.filter(\.selected).isEmpty || model.isRemoving)
        }
    }
}

private struct LeftoverRow: View {
    @Binding var item: LeftoverItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.selected).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Pill(text: item.reason.label, color: item.reason == .appBundle ? .blue : .secondary)
                    Text(item.location)
                    if item.needsAdmin {
                        Label("admin", systemImage: "lock.fill").labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { Finder.reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
        }
        .help(item.url.path)
    }
}

private struct AppRow: View {
    let app: AppInfo
    let size: Int64?
    let largest: Int64
    let showBar: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(app.version.isEmpty ? app.bundleID : "\(app.version) · \(app.bundleID)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if showBar, let size, largest > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule().fill(Theme.gradient(Theme.blue))
                                .frame(width: max(3, geo.size.width * Double(size) / Double(largest)))
                        }
                    }
                    .frame(height: 4)
                }
            }
            Spacer(minLength: 6)
            if let size {
                Text(Fmt.bytes(size))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
