import SwiftUI
import AppKit

struct SunburstSegment {
    let node: FileNode
    let depth: Int
    let start: Double // radianti, 0 = ore 12, senso orario
    let end: Double
    let colorIndex: Int
    /// Arco che raggruppa gli elementi troppo piccoli per essere disegnati (`node` è la cartella madre).
    var isRest = false
}

/// Grafico a anelli concentrici: ogni anello è un livello di profondità,
/// l'ampiezza dell'arco è proporzionale allo spazio occupato.
struct SunburstView: View {
    let root: FileNode
    let revision: Int
    @Binding var hovered: FileNode?
    var onSelect: (FileNode) -> Void
    var onBack: () -> Void

    static let maxDepth = 4
    /// Archi più stretti di così (in punti, sul bordo interno) confluiscono in un unico arco "altri".
    private static let minArc = 7.0

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size)
            let segments = Self.segments(for: root, layout: layout)

            ZStack {
                Canvas { context, _ in
                    for segment in segments {
                        guard let path = layout.path(for: segment) else { continue }
                        context.fill(path, with: .color(color(for: segment)))
                        if !segment.isRest, segment.node === hovered {
                            context.fill(path, with: .color(.white.opacity(0.22)))
                        }
                    }
                    let disc = Path(ellipseIn: CGRect(
                        x: layout.center.x - layout.inner + 3, y: layout.center.y - layout.inner + 3,
                        width: (layout.inner - 3) * 2, height: (layout.inner - 3) * 2))
                    context.fill(disc, with: .color(.primary.opacity(0.05)))
                }

                centerLabel(width: layout.inner * 1.45)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let segment = layout.hit(point, in: segments)
                    hovered = segment?.isRest == false ? segment?.node : nil
                case .ended: hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                if layout.isCenter(value.location) {
                    onBack()
                } else if let segment = layout.hit(value.location, in: segments), !segment.isRest {
                    onSelect(segment.node)
                }
            })
            .id(revision)
        }
    }

    private func centerLabel(width: Double) -> some View {
        let focus = hovered ?? root
        return VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: focus.url.path))
                .resizable().frame(width: 28, height: 28)
                .padding(.bottom, 2)
            Text(focus.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.75)
            Text(Fmt.bytes(focus.size))
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Group {
                if hovered != nil, root.size > 0 {
                    Text(Double(focus.size) / Double(root.size), format: .percent.precision(.fractionLength(1)))
                } else if root.parent != nil {
                    Text("clic per risalire")
                } else {
                    Text(" ")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(width: max(40, width))
        .allowsHitTesting(false)
    }

    private func color(for segment: SunburstSegment) -> Color {
        if segment.node.isAggregate && !segment.isRest { return Color.secondary.opacity(0.25) }
        // Gli archi "altri" riprendono il colore del ramo, molto attenuato (grigio al primo livello).
        if segment.isRest && segment.colorIndex < 0 { return Color.secondary.opacity(hovered == nil ? 0.25 : 0.1) }
        let base = Theme.chart[segment.colorIndex % Theme.chart.count]
        if segment.isRest { return Color(nsColor: base).opacity(hovered == nil ? 0.28 : 0.12) }
        // Più si scende di livello, più il colore schiarisce; i file sono più tenui delle cartelle.
        let fraction = min(0.55, Double(segment.depth) * 0.12 + (segment.node.isDirectory ? 0 : 0.12))
        let color = Color(base.blended(withFraction: fraction, of: .white) ?? base)
        // Con un elemento evidenziato, il resto del grafico passa in secondo piano.
        if let hovered, !segment.node.ancestry.contains(where: { $0 === hovered }) {
            return color.opacity(0.45)
        }
        return color
    }

    static func segments(for root: FileNode, layout: Layout) -> [SunburstSegment] {
        var out: [SunburstSegment] = []
        func walk(_ node: FileNode, depth: Int, start: Double, span: Double, colorIndex: Int?) {
            guard node.size > 0, depth < maxDepth else { return }
            let minSpan = minArc / (layout.inner + layout.ring * Double(depth))
            var angle = start
            var restSpan = 0.0
            for (index, child) in node.children.enumerated() where child.size > 0 {
                let childSpan = span * Double(child.size) / Double(node.size)
                guard childSpan >= minSpan else {
                    restSpan += childSpan
                    continue
                }
                defer { angle += childSpan }
                let childColor = colorIndex ?? index
                out.append(SunburstSegment(
                    node: child, depth: depth, start: angle, end: angle + childSpan, colorIndex: childColor))
                if child.isDirectory {
                    walk(child, depth: depth + 1, start: angle, span: childSpan, colorIndex: childColor)
                }
            }
            // Gli elementi minuscoli diventano un unico arco grigio in coda, invece di tante righe sottili.
            if restSpan >= minSpan / 2 {
                out.append(SunburstSegment(
                    node: node, depth: depth, start: angle, end: angle + restSpan,
                    colorIndex: colorIndex ?? -1, isRest: true))
            }
        }
        walk(root, depth: 0, start: 0, span: 2 * .pi, colorIndex: nil)
        return out
    }

    struct Layout {
        let center: CGPoint
        let inner: Double
        let ring: Double

        init(size: CGSize) {
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = max(10, min(size.width, size.height) / 2 - 6)
            inner = outer * 0.34
            ring = (outer - inner) / Double(SunburstView.maxDepth)
        }

        private func point(radius: Double, angle: Double) -> CGPoint {
            // angolo 0 = ore 12; nelle coordinate SwiftUI la y cresce verso il basso.
            CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
        }

        /// Spazio tra gli archi, in punti: separa i segmenti senza bordi scuri.
        private static let gap = 1.0

        func path(for s: SunburstSegment) -> Path? {
            let r0 = inner + ring * Double(s.depth) + Self.gap
            let r1 = inner + ring * Double(s.depth + 1) - Self.gap
            // Il distacco angolare è costante in punti: più stretto sugli anelli esterni.
            let start0 = s.start + Self.gap / r0, end0 = s.end - Self.gap / r0
            let start1 = s.start + Self.gap / r1, end1 = s.end - Self.gap / r1
            guard end0 > start0, end1 > start1 else { return nil }
            let steps = max(2, Int((s.end - s.start) / 0.02))
            var path = Path()
            for i in 0...steps {
                let a = start1 + (end1 - start1) * Double(i) / Double(steps)
                let p = point(radius: r1, angle: a)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            for i in stride(from: steps, through: 0, by: -1) {
                let a = start0 + (end0 - start0) * Double(i) / Double(steps)
                path.addLine(to: point(radius: r0, angle: a))
            }
            path.closeSubpath()
            return path
        }

        func isCenter(_ p: CGPoint) -> Bool {
            hypot(p.x - center.x, p.y - center.y) < inner
        }

        func hit(_ p: CGPoint, in segments: [SunburstSegment]) -> SunburstSegment? {
            let dx = p.x - center.x
            let dy = p.y - center.y
            let distance = hypot(dx, dy)
            guard distance >= inner else { return nil }
            let depth = Int((distance - inner) / ring)
            guard depth < SunburstView.maxDepth else { return nil }
            var angle = atan2(dx, -dy) // 0 = ore 12, senso orario
            if angle < 0 { angle += 2 * .pi }
            return segments.first { $0.depth == depth && angle >= $0.start && angle < $0.end }
        }
    }
}
