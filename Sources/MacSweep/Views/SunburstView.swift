import SwiftUI

struct SunburstSegment {
    let node: FileNode
    let depth: Int
    let start: Double // radianti, 0 = ore 12, senso orario
    let end: Double
    let hue: Double
}

/// Grafico a anelli concentrici: ogni anello è un livello di profondità,
/// l'ampiezza dell'arco è proporzionale allo spazio occupato.
struct SunburstView: View {
    let root: FileNode
    let revision: Int
    @Binding var hovered: FileNode?
    var onSelect: (FileNode) -> Void
    var onBack: () -> Void

    static let maxDepth = 5
    private static let minSpan = 0.004

    var body: some View {
        GeometryReader { geo in
            let segments = Self.segments(for: root)
            let layout = Layout(size: geo.size)

            ZStack {
                Canvas { context, _ in
                    for segment in segments {
                        let path = layout.path(for: segment)
                        context.fill(path, with: .color(color(for: segment)))
                        if segment.node === hovered {
                            context.stroke(path, with: .color(.primary), lineWidth: 2)
                        } else {
                            context.stroke(path, with: .color(.black.opacity(0.18)), lineWidth: 0.5)
                        }
                    }
                }

                VStack(spacing: 4) {
                    let focus = hovered ?? root
                    Image(systemName: focus.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(.secondary)
                    Text(focus.name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(Fmt.bytes(focus.size))
                        .font(.title3.monospacedDigit())
                    if hovered == nil && root.parent != nil {
                        Text("clic al centro per risalire").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: layout.inner * 1.7)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = layout.hit(point, in: segments)?.node
                case .ended: hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                if layout.isCenter(value.location) {
                    onBack()
                } else if let segment = layout.hit(value.location, in: segments) {
                    onSelect(segment.node)
                }
            })
            .id(revision)
        }
    }

    private func color(for segment: SunburstSegment) -> Color {
        if segment.node.isAggregate { return Color.gray.opacity(0.35) }
        let brightness = 0.92 - Double(segment.depth) * 0.08
        let saturation = segment.node.isDirectory ? 0.62 : 0.35
        return Color(hue: segment.hue, saturation: saturation, brightness: brightness)
    }

    static func segments(for root: FileNode) -> [SunburstSegment] {
        var out: [SunburstSegment] = []
        func walk(_ node: FileNode, depth: Int, start: Double, span: Double, hue: Double?) {
            guard node.size > 0, depth < maxDepth else { return }
            var angle = start
            for child in node.children where child.size > 0 {
                let childSpan = span * Double(child.size) / Double(node.size)
                defer { angle += childSpan }
                guard childSpan >= minSpan else { continue }
                let childHue = hue ?? ((angle + childSpan / 2) / (2 * .pi))
                out.append(SunburstSegment(node: child, depth: depth, start: angle, end: angle + childSpan, hue: childHue))
                if child.isDirectory {
                    walk(child, depth: depth + 1, start: angle, span: childSpan, hue: childHue)
                }
            }
        }
        walk(root, depth: 0, start: 0, span: 2 * .pi, hue: nil)
        return out
    }

    private struct Layout {
        let center: CGPoint
        let inner: Double
        let ring: Double

        init(size: CGSize) {
            center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = max(10, min(size.width, size.height) / 2 - 6)
            inner = outer * 0.24
            ring = (outer - inner) / Double(SunburstView.maxDepth)
        }

        private func point(radius: Double, angle: Double) -> CGPoint {
            // angolo 0 = ore 12; nelle coordinate SwiftUI la y cresce verso il basso.
            CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
        }

        func path(for s: SunburstSegment) -> Path {
            let r0 = inner + ring * Double(s.depth)
            let r1 = r0 + ring - 1
            let steps = max(2, Int((s.end - s.start) / 0.03))
            var path = Path()
            for i in 0...steps {
                let a = s.start + (s.end - s.start) * Double(i) / Double(steps)
                let p = point(radius: r1, angle: a)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            for i in stride(from: steps, through: 0, by: -1) {
                let a = s.start + (s.end - s.start) * Double(i) / Double(steps)
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
