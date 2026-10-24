import AppKit

// Placeholder app icon. The owner replaces it with a real one before 1.0 (new PNGs under the same
// names in Cards/Assets.xcassets/AppIcon.appiconset), and then this script can go.
//
// Drawn from Palette's tokens so the icon and the app share one set of colors. Run from the repo
// root:
//   swiftc -parse-as-library scripts/make-icon.swift Cards/Palette.swift -o build/make-icon
//   build/make-icon Cards/Assets.xcassets/AppIcon.appiconset
// Each size is drawn at its own pixel size (not scaled down from one master), so the output is
// the same every run and small sizes stay crisp.

@main
enum MakeIcon {
    /// (file name, pixel size) for every slot of a macOS AppIcon.
    static let files: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    static func main() throws {
        let out = URL(filePath: CommandLine.arguments.dropFirst().first ?? ".", directoryHint: .isDirectory)
        for (name, px) in files {
            try png(px).write(to: out.appending(path: name), options: .atomic)
        }
    }

    static func png(_ px: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: px, height: px)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(CGFloat(px))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    /// The icon on an `s` x `s` canvas: a warm paper plate (the macOS 824/1024 body with its soft
    /// shadow) holding a small fan of three cards, the front one with the tan ribbon and ink lines.
    static func draw(_ s: CGFloat) {
        func opaque(_ c: NSColor) -> NSColor { c.withAlphaComponent(1) }
        let body = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8046, height: s * 0.8046)
        let plate = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
        shadow.shadowBlurRadius = s * 0.025
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.set()
        opaque(Palette.ribbon).setFill()
        plate.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        NSGradient(colors: [opaque(Palette.paper), opaque(Palette.ribbon)])?.draw(in: body, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        Palette.line.setStroke()
        plate.lineWidth = max(1, s * 0.004)
        plate.stroke()

        // Three cards, back to front, each a little lower and further left than the one behind.
        let w = s * 0.40, h = s * 0.46, r = s * 0.045
        let origin = NSPoint(x: s * 0.5 - w / 2 + s * 0.05, y: s * 0.5 - h / 2 - s * 0.04)
        for step in (0..<3).reversed() {
            let dx = -CGFloat(2 - step) * s * 0.045, dy = CGFloat(2 - step) * s * 0.045
            let rect = NSRect(x: origin.x + dx, y: origin.y + dy, width: w, height: h)
            let card = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
            NSGraphicsContext.saveGraphicsState()
            let lift = NSShadow()
            lift.shadowOffset = NSSize(width: 0, height: -s * 0.006)
            lift.shadowBlurRadius = s * 0.014
            lift.shadowColor = Palette.line.withAlphaComponent(0.45)
            lift.set()
            Palette.sheen.withAlphaComponent(0.92).setFill()
            card.fill()
            NSGraphicsContext.restoreGraphicsState()
            Palette.line.setStroke()
            card.lineWidth = max(1, s * 0.004)
            card.stroke()
            guard step == 0 else { continue }
            NSGraphicsContext.saveGraphicsState()
            card.addClip()
            opaque(Palette.ribbon).setFill()
            NSRect(x: rect.minX, y: rect.maxY - h * 0.2, width: w, height: h * 0.2).fill()
            NSGraphicsContext.restoreGraphicsState()
            opaque(Palette.inkSoft).setFill()
            for (i, width) in [0.72, 0.58, 0.66].enumerated() {
                let bar = NSRect(x: rect.minX + w * 0.12, y: rect.maxY - h * (0.34 + 0.14 * CGFloat(i)),
                                 width: w * width, height: h * 0.05)
                NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
            }
        }
    }
}
