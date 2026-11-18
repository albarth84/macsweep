import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            UpdatesSettings()
                .tabItem { Label("Aggiornamenti", systemImage: "arrow.down.circle") }
            AboutSettings()
                .tabItem { Label("Informazioni", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 470)
    }
}

private struct UpdatesSettings: View {
    @Bindable private var updater = UpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AppLogo(size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacSweep").font(.title2.weight(.bold))
                    Text("Versione installata: \(updater.currentVersionString)").foregroundStyle(.secondary)
                    if let last = updater.lastCheck {
                        Text("Ultimo controllo: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button {
                    Task { await updater.check() }
                } label: { Label("Controlla ora", systemImage: "arrow.clockwise") }
                    .disabled(updater.state == .checking || updater.state == .installing || isDownloading)
            }

            Toggle("Controlla automaticamente gli aggiornamenti all'avvio", isOn: $updater.automaticChecks)

            statusCard
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var isDownloading: Bool {
        if case .downloading = updater.state { return true }
        return false
    }

    @ViewBuilder
    private var statusCard: some View {
        switch updater.state {
        case .idle:
            status(symbol: "clock", colors: Theme.gray, title: "Nessun controllo ancora eseguito",
                   message: "Premi \"Controlla ora\" per cercare nuove versioni su GitHub.")
        case .checking:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Ricerca aggiornamenti…")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        case .upToDate:
            status(symbol: "checkmark", colors: Theme.green, title: "MacSweep è aggiornato",
                   message: "Hai l'ultima versione disponibile.")
        case .failed(let message):
            status(symbol: "exclamationmark.triangle.fill", colors: Theme.orange,
                   title: "Controllo non riuscito", message: message)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Text("Download dell'aggiornamento…").font(.headline)
                ProgressView(value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .card()
        case .installing:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Installazione: MacSweep si riavvierà tra un istante…")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        case .available(let release):
            availableCard(release)
        }
    }

    private func availableCard(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.down", colors: Theme.brand, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disponibile la versione \(release.version?.description ?? release.tagName)")
                        .font(.headline)
                    if let date = release.publishedAt {
                        Text("Pubblicata il \(date.formatted(date: .long, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let body = release.body, !body.isEmpty {
                ScrollView {
                    Text((try? AttributedString(markdown: body, options: .init(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Link("Note su GitHub", destination: release.htmlURL)
                Spacer()
                if updater.canInstall {
                    Button { Task { await updater.downloadAndInstall() } } label: {
                        Label("Scarica e installa", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.gradient)
                } else {
                    Text("Avvio da sviluppo o cartella non scrivibile: scarica manualmente.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Apri la release", destination: release.htmlURL)
                }
            }
        }
        .card()
    }

    private func status(symbol: String, colors: [Color], title: String, message: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, colors: colors, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            AppLogo(size: 84)
            Text("MacSweep").font(.title.weight(.bold))
            Text("Versione \(UpdateManager.shared.currentVersionString)").foregroundStyle(.secondary)
            Text("Analisi dello spazio e pulizia sicura per macOS.\nTutto ciò che elimini passa dal Cestino.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("github.com/\(UpdateManager.repository)", destination: UpdateManager.repositoryURL)
            Text("Licenza MIT").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Avviso nella sidebar quando c'è una nuova versione.
struct UpdateBadge: View {
    let updater = UpdateManager.shared

    var body: some View {
        if let release = updater.availableRelease {
            SettingsLink {
                HStack(spacing: 8) {
                    IconTile(symbol: "arrow.down", colors: Theme.brand, size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Aggiornamento disponibile").font(.caption.weight(.semibold))
                        Text("Versione \(release.version?.description ?? release.tagName)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
        }
    }
}
