import SwiftUI
import Combine
import AppKit

/// Schermata iniziale finché manca l'Accesso completo al disco.
///
/// Senza questo permesso macOS chiede l'autorizzazione cartella per cartella (Download, Scrivania,
/// Documenti, dati di altre app…). MacSweep non legge nulla finché l'utente non sceglie: concedere
/// l'accesso completo (una volta sola, resta valido anche dopo gli aggiornamenti) oppure continuare
/// con accesso limitato.
struct FullDiskAccessOnboarding: View {
    var onGranted: () -> Void
    var onContinueLimited: () -> Void

    @State private var granted = Permissions.hasFullDiskAccess()
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AppLogo(size: 88).padding(.top, 30)

                VStack(spacing: 8) {
                    Text("MacSweep ha bisogno dell'Accesso completo al disco")
                        .font(.system(size: 26, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("Un solo permesso, concesso una volta: resta valido anche dopo gli aggiornamenti.")
                        .font(.title3).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    reason("checkmark.shield.fill", Theme.green,
                           "Niente richieste cartella per cartella",
                           "Senza questo permesso macOS chiederebbe l'accesso a Download, Scrivania, Documenti e ai dati di ogni app, uno alla volta.")
                    reason("chart.pie.fill", Theme.teal,
                           "Analisi completa e precisa",
                           "Cache, container, file orfani e dati delle app sono in cartelle protette: senza accesso completo restano invisibili.")
                    reason("trash.fill", Theme.orange,
                           "Nulla viene eliminato senza conferma",
                           "MacSweep legge per analizzare. Ogni eliminazione la scegli tu e passa dal Cestino.")
                }
                .frame(maxWidth: 560)
                .card(padding: 20)

                if granted {
                    grantedCard
                } else {
                    steps
                }

                if !granted {
                    Button("Continua con accesso limitato") { onContinueLimited() }
                        .buttonStyle(.link)
                        .help("macOS chiederà il permesso per ogni cartella protetta e alcune analisi saranno incomplete.")
                    Text("Con accesso limitato macOS chiederà il permesso per ogni cartella protetta.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.pageBackground)
        .onReceive(timer) { _ in
            if !granted && Permissions.hasFullDiskAccess() {
                withAnimation(.spring) { granted = true }
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Come concederlo").font(.headline)
            step(1, "Apri Impostazioni di Sistema › Privacy e sicurezza › Accesso completo al disco.") {
                Button { Permissions.openFullDiskAccessSettings() } label: {
                    Label("Apri Impostazioni", systemImage: "gearshape.fill")
                }
                .buttonStyle(.gradient)
            }
            step(2, "Attiva l'interruttore accanto a MacSweep. Se non è nell'elenco, premi \"+\" e scegli MacSweep, oppure trascinalo nell'elenco.") {
                Button { Finder.reveal(URL(fileURLWithPath: Bundle.main.bundlePath)) } label: {
                    Label("Mostra MacSweep nel Finder", systemImage: "folder")
                }
            }
            step(3, "Torna qui: MacSweep se ne accorge da solo.") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("In attesa del permesso…").foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .card(padding: 20)
    }

    private var grantedCard: some View {
        VStack(spacing: 14) {
            IconTile(symbol: "checkmark", colors: Theme.green, size: 52)
            Text("Accesso completo al disco attivo").font(.title2.weight(.semibold))
            Text("Se macOS te lo chiede, riavvia MacSweep perché il permesso abbia effetto su tutte le cartelle.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Riavvia MacSweep") { Relauncher.relaunch() }
                Button { onGranted() } label: { Label("Inizia", systemImage: "arrow.right") }
                    .buttonStyle(.gradient(Theme.green))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 560)
        .card(padding: 22)
        .transition(.scale.combined(with: .opacity))
    }

    private func reason(_ symbol: String, _ colors: [Color], _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, colors: colors, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step<Accessory: View>(_ number: Int, _ text: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.gradient(Theme.brand), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(text).fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }
}

enum Relauncher {
    /// Riapre MacSweep dopo la chiusura (serve dopo aver concesso un permesso).
    static func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { NSApp.terminate(nil); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
