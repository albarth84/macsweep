import SwiftUI

struct OverviewView: View {
    let volume: VolumeInfo
    let cleanup: CleanupModel
    let orphans: OrphansModel
    let apps: AppsModel
    @Binding var selection: SidebarItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Panoramica", subtitle: "Lo stato del tuo disco e cosa puoi liberare.",
                           symbol: SidebarItem.overview.symbol, colors: Theme.brand)
                    .padding(.horizontal, -24)

                HStack(alignment: .top, spacing: 20) {
                    diskCard
                    reclaimCard
                }

                Text("Strumenti").font(.headline).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(SidebarItem.allCases.filter { $0 != .overview }) { item in
                        Button { selection = item } label: { ToolCard(item: item, value: value(for: item)) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        // Nessuna analisi automatica all'avvio: leggere Download, Scrivania e dati di altre app
        // fa comparire le richieste di permesso di macOS, che devono seguire un'azione dell'utente.
    }

    private var usedFraction: Double {
        volume.total > 0 ? Double(volume.used) / Double(volume.total) : 0
    }

    private var diskCard: some View {
        HStack(spacing: 24) {
            ZStack {
                RingGauge(progress: usedFraction, lineWidth: 18,
                          colors: usedFraction > 0.9 ? Theme.red : Theme.brand + [Color(hex: 0x0EA5E9)])
                VStack(spacing: 0) {
                    Text(usedFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("occupato").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 10) {
                Text("Macintosh HD").font(.title3.weight(.semibold))
                Text(Fmt.bytes(volume.availableImportant))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                + Text(" disponibili").font(.title3).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    LegendDot(color: .accentColor, title: "Usato", value: Fmt.bytes(volume.used))
                    LegendDot(color: .orange, title: "Eliminabile dal sistema", value: Fmt.bytes(volume.purgeable))
                    LegendDot(color: .secondary.opacity(0.4), title: "Libero", value: Fmt.bytes(volume.available))
                    LegendDot(color: .primary.opacity(0.6), title: "Capacità", value: Fmt.bytes(volume.total))
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 22)
        .frame(maxWidth: .infinity)
    }

    private var reclaimCard: some View {
        let safe = cleanup.categories.filter { $0.risk == .safe }.reduce(Int64(0)) { $0 + cleanup.total($1.id) }
        let review = cleanup.categories.filter { $0.risk != .safe }.reduce(Int64(0)) { $0 + cleanup.total($1.id) }
        let orphanBytes = orphans.items.filter { $0.confidence == .high }.reduce(Int64(0)) { $0 + $1.size }
        let loading = !cleanup.analyzing.isEmpty || orphans.isScanning
        let analyzed = cleanup.hasAnalyzed || orphans.hasScanned

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spazio recuperabile").font(.title3.weight(.semibold))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            Text(Fmt.bytes(safe + orphanBytes))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gradient(Theme.pink))
                .contentTransition(.numericText())
            Text("in sicurezza, più \(Fmt.bytes(review)) da verificare")
                .font(.callout).foregroundStyle(.secondary)
            SegmentBar(segments: [
                .init(value: Double(safe), color: Color(hex: 0xF472B6)),
                .init(value: Double(orphanBytes), color: Color(hex: 0xF59E0B)),
                .init(value: Double(review), color: Color.secondary.opacity(0.35)),
            ], height: 10)
            HStack(spacing: 14) {
                LegendDot(color: Color(hex: 0xF472B6), title: "Pulizia", value: Fmt.bytes(safe))
                LegendDot(color: Color(hex: 0xF59E0B), title: "Orfani", value: Fmt.bytes(orphanBytes))
            }
            Spacer(minLength: 0)
            if analyzed || loading {
                Button { selection = .cleanup } label: { Label("Vai alla pulizia", systemImage: "sparkles") }
                    .buttonStyle(.gradient(Theme.pink))
            } else {
                Button {
                    cleanup.analyzeAll()
                    orphans.scan()
                    if apps.apps.isEmpty { apps.load() }
                } label: { Label("Analizza il Mac", systemImage: "play.fill") }
                    .buttonStyle(.gradient(Theme.pink))
            }
        }
        .animation(.default, value: safe)
        .card(padding: 22)
        .frame(maxWidth: 380)
    }

    private func value(for item: SidebarItem) -> String? {
        switch item {
        case .cleanup:
            let total = cleanup.categories.reduce(Int64(0)) { $0 + cleanup.total($1.id) }
            return total > 0 ? Fmt.bytes(total) : nil
        case .orphans:
            return orphans.hasScanned ? "\(orphans.items.count) elementi" : nil
        case .apps:
            return apps.apps.isEmpty ? nil : "\(apps.apps.count) app"
        default:
            return nil
        }
    }
}

private struct ToolCard: View {
    let item: SidebarItem
    let value: String?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: item.symbol, colors: item.colors, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if let value {
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .card(padding: 14)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
    }
}
