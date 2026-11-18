import SwiftUI
import AppKit

@main
struct MacSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        CLIReport.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("MacSweep") {
            ContentView()
                .frame(minWidth: 1050, minHeight: 680)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand()
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Necessario quando l'eseguibile viene lanciato fuori da un bundle .app (es. `swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Voce di menu "Controlla aggiornamenti…": apre le Impostazioni e avvia il controllo.
private struct CheckForUpdatesCommand: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Controlla aggiornamenti…") {
            openSettings()
            Task { await UpdateManager.shared.check() }
        }
    }
}
