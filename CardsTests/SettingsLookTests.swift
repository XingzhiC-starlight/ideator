import XCTest
@testable import Ideator

/// SETTINGS-DESIGN.md's look: the palette's contrast (A1).
final class SettingsLookTests: XCTestCase {
    private let palette = Palette.Settings.self

    override func tearDown() {
        Palette.Settings.increaseContrastOverride = nil
    }

    func testEveryTextPairReadsAtFourAndAHalfToOneAndEveryEdgeAndGlyphAtThree() {
        Palette.Settings.increaseContrastOverride = false
        let text: [(String, NSColor, NSColor)] = [
            ("ink on canvas", palette.ink, palette.canvas),
            ("ink on surface", palette.ink, palette.surface),
            ("ink on wash", palette.ink, palette.wash),
            ("inkInverse on inverse", palette.inkInverse, palette.inverse),
            ("inkInverse on inverseRaised", palette.inkInverse, palette.inverseRaised),
            ("inkMuted on canvas", palette.inkMuted, palette.canvas),
            ("inkMuted on surface", palette.inkMuted, palette.surface),
            ("inkInverseMuted on inverse", palette.inkInverseMuted, palette.inverse),
        ]
        let graphics: [(String, NSColor, NSColor)] = [
            ("border on canvas", palette.border, palette.canvas),
            ("border on surface", palette.border, palette.surface),
            ("accent on canvas", palette.accent, palette.canvas),
            ("the check on accent", palette.inkInverse, palette.accent),
            ("successStrong on canvas", palette.successStrong, palette.canvas),
            ("warningStrong on canvas", palette.warningStrong, palette.canvas),
            ("dangerStrong on canvas", palette.dangerStrong, palette.canvas),
        ]
        for (pair, foreground, background) in text {
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5, pair)
        }
        for (pair, foreground, background) in graphics {
            XCTAssertGreaterThanOrEqual(contrast(foreground, background), 3, pair)
        }
    }

    func testIncreaseContrastTurnsBordersAndMutedInkToInk() {
        Palette.Settings.increaseContrastOverride = false
        XCTAssertNotEqual(srgb(palette.border), srgb(palette.ink))
        XCTAssertNotEqual(srgb(palette.inkMuted), srgb(palette.ink))

        Palette.Settings.increaseContrastOverride = true

        XCTAssertEqual(srgb(palette.border), srgb(palette.ink))
        XCTAssertEqual(srgb(palette.inkMuted), srgb(palette.ink))
        XCTAssertEqual(srgb(palette.inkInverseMuted), srgb(palette.inkInverse))
    }

    private func srgb(_ color: NSColor) -> [CGFloat] {
        let c = color.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    /// WCAG 2.2's contrast ratio, from relative luminance.
    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            let rgb = srgb(color).prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
