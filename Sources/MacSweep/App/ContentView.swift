import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, diskMap, deepScan, cleanup, whatsapp, apps, orphans

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Panoramica"
        case .diskMap: "Mappa disco"
        case .deepScan: "Scansione file"
        case .cleanup: "Pulizia"
        case .whatsapp: "WhatsApp"
        case .apps: "Applicazioni"
        case .orphans: "File orfani"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Stato del disco"
        case .diskMap: "Dove finisce lo spazio, cartella per cartella"
        case .deepScan: "Analisi per tipo di file di un'unità"
        case .cleanup: "Cache, log, dati IA, sviluppo"
        case .whatsapp: "Stati e media delle chat, chat per chat"
        case .apps: "Disinstalla app e tutti i loro file"
        case .orphans: "Dati di app già disinstallate"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .diskMap: "chart.pie.fill"
        case .deepScan: "magnifyingglass"
        case .cleanup: "sparkles"
        case .whatsapp: "bubble.left.and.bubble.right.fill"
        case .apps: "square.grid.2x2.fill"
        case .orphans: "questionmark.folder.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .overview: Theme.brand
        case .diskMap: Theme.teal
        case .deepScan: Theme.green
        case .cleanup: Theme.pink
        case .whatsapp: WhatsAppView.colors
        case .apps: Theme.blue
        case .orphans: Theme.orange
        }
    }
}

struct ContentView: View {
    // `-page deepScan` all'avvio apre direttamente una sezione (comodo in sviluppo).
    @State private var selection: SidebarItem? =
        UserDefaults.standard.string(forKey: "page").flatMap(SidebarItem.init(rawValue:)) ?? .overview
    @State private var diskModel = DiskMapModel()
    @State private var deepScanModel = DeepScanModel()
    @State private var cleanupModel = CleanupModel()
    @State private var appsModel = AppsModel()
    @State private var orphansModel = OrphansModel()
    @State private var whatsAppModel = WhatsAppModel()
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SidebarItem.allCases) { item in
                        HStack(spacing: 10) {
                            IconTile(symbol: item.symbol, colors: item.colors, size: 24)
                            Text(item.title)
                        }
                        .padding(.vertical, 2)
                        .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    AppLogo(size: 30)
                    Text("MacSweep").font(.title3.weight(.bold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .safeAreaInset(edge: .bottom) {
                SidebarDiskFooter(volume: diskModel.volume)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                if !hasFullDiskAccess {
                    FullDiskAccessBanner { hasFullDiskAccess = Permissions.hasFullDiskAccess() }
                }
                switch selection ?? .overview {
                case .overview:
                    OverviewView(volume: diskModel.volume, cleanup: cleanupModel, orphans: orphansModel,
                                 apps: appsModel, selection: $selection)
                case .diskMap: DiskMapView(model: diskModel)
                case .deepScan: DeepScanView(model: deepScanModel)
                case .cleanup: CleanupView(model: cleanupModel)
                case .whatsapp: WhatsAppView(model: whatsAppModel)
                case .apps: AppsView(model: appsModel)
                case .orphans: OrphansView(model: orphansModel)
                }
            }
            .background(Theme.pageBackground)
        }
    }
}

/// Logo disegnato in codice: anelli concentrici in stile sunburst.
struct AppLogo: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.gradient([Color(hex: 0x312E81), Color(hex: 0x6D28D9)]))
            ForEach(0..<3) { ring in
                let radius = size * (0.18 + 0.1 * Double(ring))
                ForEach(0..<3) { arc in
                    Circle()
                        .trim(from: Double(arc) / 3 + 0.02, to: Double(arc + 1) / 3 - 0.02 - Double(ring) * 0.04)
                        .stroke(Color(Theme.chart[(ring * 3 + arc) % Theme.chart.count]),
                                style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                        .frame(width: radius * 2, height: radius * 2)
                        .rotationEffect(.degrees(Double(ring) * 40 - 90))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SidebarDiskFooter: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
                Text("Macintosh HD").font(.caption.weight(.semibold))
                Spacer()
            }
            SegmentBar(segments: [
                .init(value: Double(volume.used), color: .accentColor),
                .init(value: Double(volume.purgeable), color: .orange.opacity(0.8)),
            ], total: Double(max(1, volume.total)), height: 6)
            Text("\(Fmt.bytes(volume.availableImportant)) disponibili su \(Fmt.bytes(volume.total))")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }
}

struct FullDiskAccessBanner: View {
    var onRecheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "lock.shield.fill", colors: Theme.orange, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accesso completo al disco non attivo").font(.callout.weight(.semibold))
                Text("Senza questo permesso alcune cartelle (Container, Mail, Safari…) non vengono analizzate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apri Impostazioni") { Permissions.openFullDiskAccessSettings() }
            Button("Ricontrolla", action: onRecheck)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
    }
}
