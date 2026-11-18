// Genera Resources/AppIcon.icns. Uso: swift scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Sfondo: squircle con gradiente (margine come le icone macOS).
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let background = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [color(0x6D28D9), color(0x312E81)])!.draw(in: background, angle: -70)

    // Anelli sunburst.
    let center = NSPoint(x: s / 2, y: s / 2)
    let palette: [UInt32] = [0x22D3EE, 0x818CF8, 0xF472B6, 0xFBBF24, 0x34D399, 0xF97316, 0xA78BFA, 0x38BDF8, 0xFB7185]
    let spans: [[CGFloat]] = [[0.46, 0.30, 0.24], [0.30, 0.16, 0.22, 0.12, 0.2], [0.18, 0.1, 0.14, 0.08, 0.12, 0.1, 0.08]]
    var colorIndex = 0
    for (ring, parts) in spans.enumerated() {
        let radius = rect.width * (0.17 + 0.105 * CGFloat(ring))
        let width = rect.width * 0.095
        var start: CGFloat = 90
        let usable: CGFloat = ring == 2 ? 300 : 360
        for part in parts {
            let sweep = usable * part
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: start - 1.5, endAngle: start - sweep + 1.5,
                           clockwise: true)
            path.lineWidth = width
            path.lineCapStyle = .butt
            color(palette[colorIndex % palette.count]).withAlphaComponent(1 - CGFloat(ring) * 0.12).setStroke()
            path.stroke()
            colorIndex += 1
            start -= sweep
        }
    }
    // Centro.
    let dot = rect.width * 0.09
    color(0xFFFFFF).withAlphaComponent(0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "iconutil failed")
