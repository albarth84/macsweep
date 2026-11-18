import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let brand = [Color(hex: 0x6366F1), Color(hex: 0xA855F7)]
    static let teal = [Color(hex: 0x14B8A6), Color(hex: 0x0EA5E9)]
    static let pink = [Color(hex: 0xF472B6), Color(hex: 0xFB923C)]
    static let blue = [Color(hex: 0x3B82F6), Color(hex: 0x6366F1)]
    static let orange = [Color(hex: 0xF59E0B), Color(hex: 0xEF4444)]
    static let green = [Color(hex: 0x22C55E), Color(hex: 0x14B8A6)]
    static let red = [Color(hex: 0xF43F5E), Color(hex: 0xDC2626)]
    static let gray = [Color(hex: 0x94A3B8), Color(hex: 0x64748B)]

    /// Palette categoriale per i grafici.
    static let chart: [NSColor] = [
        0x6366F1, 0x0EA5E9, 0x14B8A6, 0x22C55E, 0xEAB308, 0xF97316, 0xEF4444, 0xEC4899, 0xA855F7, 0x3B82F6,
    ].map { NSColor(Color(hex: $0)) }

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
}

/// Icona SF Symbol su riquadro arrotondato con gradiente.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.gradient(colors))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white))
            .shadow(color: (colors.first ?? .black).opacity(0.25), radius: size * 0.12, y: size * 0.05)
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat
    var highlighted: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.07),
                                  lineWidth: highlighted ? 2 : 1))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, highlighted: highlighted))
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, colors: colors, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, symbol: String, colors: [Color]) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, colors: colors) { EmptyView() }
    }
}

/// Anello di avanzamento con gradiente angolare.
struct RingGauge: View {
    let progress: Double
    var lineWidth: CGFloat = 16
    var colors: [Color] = Theme.brand

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: colors + [colors.first ?? .accentColor], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

/// Barra orizzontale a segmenti proporzionali.
struct SegmentBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var total: Double? = nil
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let sum = max(1, total ?? segments.reduce(0) { $0 + $1.value })
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, geo.size.width * segment.value / sum))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

struct LegendDot: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.caption)
    }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Pulsante principale con gradiente, usato per le azioni importanti.
struct GradientButtonStyle: ButtonStyle {
    var colors: [Color] = Theme.brand
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Theme.gradient(colors), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .shadow(color: (colors.first ?? .black).opacity(isEnabled ? 0.3 : 0), radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradient: GradientButtonStyle { GradientButtonStyle() }
    static func gradient(_ colors: [Color]) -> GradientButtonStyle { GradientButtonStyle(colors: colors) }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var colors: [Color] = Theme.brand

    var body: some View {
        VStack(spacing: 14) {
            IconTile(symbol: symbol, colors: colors, size: 64)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
