import SwiftUI
import AppKit

struct AppsView: View {
    @Bindable var model: AppsModel

    var body: some View {
        HSplitView {
            appList.frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
            detail.frame(minWidth: 460, maxWidth: .infinity)
        }
        .navigationTitle("Applicazioni")
        .toolbar {
            Button { model.load() } label: { Label("Aggiorna", systemImage: "arrow.clockwise") }
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
            TextField("Cerca app", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(model.filteredApps, selection: Binding(get: { model.selectedID }, set: { model.select($0) })) { app in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).lineLimit(1)
                        Text(app.version.isEmpty ? app.bundleID : "\(app.version) · \(app.bundleID)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let size = model.sizes[app.id] {
                        Text(Fmt.bytes(size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .tag(app.id)
            }
            .overlay { if model.isLoading { ProgressView() } }
            Divider()
            Text("\(model.apps.count) app installate").font(.caption).foregroundStyle(.secondary).padding(6)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            AppDetail(model: model, app: app)
        } else {
            ContentUnavailableView(
                "Seleziona un'app", systemImage: "app.dashed",
                description: Text("MacSweep cercherà preferenze, cache, container, log e servizi di avvio collegati all'app."))
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
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title2.bold())
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
            Text("\(model.leftovers.count) elementi trovati · selezionati \(Fmt.bytes(model.selectedTotal))")
                .foregroundStyle(.secondary)
            if model.isRemoving { ProgressView().controlSize(.small) }
            Button("Rimuovi selezionati…") { confirming = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.selectedTotal == 0 && model.leftovers.filter(\.selected).isEmpty || model.isRemoving)
        }
    }
}

private struct LeftoverRow: View {
    @Binding var item: LeftoverItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.selected).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(item.location)
                    Text("·")
                    Text(item.reason.label)
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
