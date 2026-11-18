import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case diskMap, cleanup, apps, orphans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diskMap: "Mappa disco"
        case .cleanup: "Pulizia"
        case .apps: "Applicazioni"
        case .orphans: "File orfani"
        }
    }

    var symbol: String {
        switch self {
        case .diskMap: "chart.pie"
        case .cleanup: "sparkles"
        case .apps: "app.badge"
        case .orphans: "questionmark.folder"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .diskMap
    @State private var diskModel = DiskMapModel()
    @State private var cleanupModel = CleanupModel()
    @State private var appsModel = AppsModel()
    @State private var orphansModel = OrphansModel()
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                if !hasFullDiskAccess {
                    FullDiskAccessBanner { hasFullDiskAccess = Permissions.hasFullDiskAccess() }
                }
                switch selection ?? .diskMap {
                case .diskMap: DiskMapView(model: diskModel)
                case .cleanup: CleanupView(model: cleanupModel)
                case .apps: AppsView(model: appsModel)
                case .orphans: OrphansView(model: orphansModel)
                }
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    var onRecheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accesso completo al disco non attivo").font(.headline)
                Text("Senza questo permesso alcune cartelle (Container, Mail, Safari…) non vengono analizzate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apri Impostazioni") { Permissions.openFullDiskAccessSettings() }
            Button("Ricontrolla", action: onRecheck)
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}
