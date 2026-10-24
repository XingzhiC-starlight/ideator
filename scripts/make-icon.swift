import AppKit

// Draws the app icon, a card and a spark on an ink plate, from Palette's colors. From the repo root:
//   swiftc -parse-as-library scripts/make-icon.swift Cards/Palette.swift -o build/make-icon
//   build/make-icon Cards/Assets.xcassets/AppIcon.appiconset

@main
enum MakeIcon {
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

    static func draw(_ s: CGFloat) {
        let body = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8046, height: s * 0.8046)
        let plate = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
        let wash = NSGradient(colors: [Palette.ink.blended(withFraction: 0.15, of: Palette.inkSoft)!,
                                       Palette.ink.blended(withFraction: 0.3, of: .black)!])!

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
        shadow.shadowBlurRadius = s * 0.025
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.set()
        Palette.ink.setFill()
        plate.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        wash.draw(in: body, angle: -90)
        // A faint rim inside the edge, so the dark plate still has an outline on a dark Dock.
        Palette.rim.withAlphaComponent(0.14).setStroke()
        plate.lineWidth = max(2, s * 0.008)
        plate.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // The card leans 6° to the left about a point just below the icon's center.
        let rect = NSRect(x: s * 0.3125, y: s * 0.2383, width: s * 0.3516, height: s * 0.4297)
        let card = NSBezierPath(roundedRect: rect, xRadius: s * 0.0527, yRadius: s * 0.0527)
        let lean = NSAffineTransform()
        lean.translateX(by: s * 0.4883, yBy: s * 0.4531)
        lean.rotate(byDegrees: 6)
        lean.translateX(by: -s * 0.4883, yBy: -s * 0.4531)
        card.transform(using: lean as AffineTransform)
        NSGraphicsContext.saveGraphicsState()
        let lift = NSShadow()
        lift.shadowOffset = NSSize(width: 0, height: -s * 0.01)
        lift.shadowBlurRadius = s * 0.027
        lift.shadowColor = NSColor.black.withAlphaComponent(0.3)
        lift.set()
        Palette.paper.withAlphaComponent(1).setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()

        // A four-point spark over the card's top-right corner, cut out of the card by a ring of plate color.
        let c = NSPoint(x: s * 0.6484, y: s * 0.6641), r = s * 0.1016, k = r * 0.13
        let spark = NSBezierPath()
        spark.move(to: NSPoint(x: c.x, y: c.y + r))
        spark.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint: NSPoint(x: c.x + k, y: c.y + k))
        spark.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint: NSPoint(x: c.x + k, y: c.y - k))
        spark.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint: NSPoint(x: c.x - k, y: c.y - k))
        spark.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint: NSPoint(x: c.x - k, y: c.y + k))
        spark.close()
        wash.interpolatedColor(atLocation: (body.maxY - c.y) / body.height).setStroke()
        spark.lineWidth = s * 0.0254
        spark.lineJoinStyle = .round
        spark.stroke()
        Palette.focus.setFill()
        spark.fill()
    }
}
