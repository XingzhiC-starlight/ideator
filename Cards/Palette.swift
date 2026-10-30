import AppKit

/// Every color the app draws with: warm beige paper, a tan ribbon, brown ink.
enum Palette {
    /// Tint over the frosted glass: the card body, and the stack's.
    static let paper = NSColor(hex: 0xF4ECDE, alpha: 0.78)
    static let ribbon = NSColor(hex: 0xE6D8BC, alpha: 0.85)
    /// The blur behind every card and the stack.
    static let glassMaterial: NSVisualEffectView.Material = .popover
    /// The soft light at a card's top edge.
    static let sheen = NSColor.white
    /// The bright specular edge just inside the outline.
    static let rim = NSColor.white
    static let ink = NSColor(hex: 0x2B2520)
    /// List markers, summary text, the card hover buttons, the edge-band chevron and Clarity when off.
    static let inkSoft = NSColor(hex: 0x716453)
    /// The "Title" placeholder.
    static let inkFaint = NSColor(hex: 0xB3A68F)
    /// New, the ribbon's icon buttons and the badge text.
    static let ribbonInk = NSColor(hex: 0x46361F)
    /// Card and stack border.
    static let line = NSColor(hex: 0x5A4630, alpha: 0.18)
    /// Fill of the hovered edge band.
    static let shade = NSColor(hex: 0x5A4630, alpha: 0.07)
    /// Stroke of the dashed slot guide.
    static let guide = NSColor(hex: 0x5A4630, alpha: 0.45)
    /// The snapping slot guide and Clarity when on.
    static let accent = NSColor(hex: 0x823F1D)
    /// The editing border: light caramel, so the card you type in is marked without a dark frame.
    static let focus = NSColor(hex: 0xDDB880)
    /// The "Desktop full" label.
    static let danger = NSColor(hex: 0x9A2818)
    /// Text selection background in the editor.
    static let highlight = NSColor(hex: 0xE8D5AE)

    /// The Settings window's own palette (SETTINGS-DESIGN.md §2.1): ivory paper, slate ink, one clay
    /// accent. Settings draws with these and nothing else; cards keep the warm paper above.
    enum Settings {
        static let canvas = NSColor(hex: 0xFAF9F6)
        static let inverse = NSColor(hex: 0x141413)
        /// Inside input wells only.
        static let surface = NSColor(hex: 0xFFFFFF)
        static let ink = NSColor(hex: 0x141413)
        static let inkInverse = NSColor(hex: 0xFAF9F6)
        static var inkMuted: NSColor { increaseContrast ? ink : NSColor(hex: 0x5E5D59) }
        static var inkInverseMuted: NSColor { increaseContrast ? inkInverse : NSColor(hex: 0xA3A198) }
        static var border: NSColor { increaseContrast ? ink : NSColor(hex: 0x858379) }
        static let inkDisabled = NSColor(hex: 0xABA9A1)
        /// Slate at 6 % over canvas.
        static let wash = NSColor(hex: 0xECEBE8)
        static let inverseRaised = NSColor(hex: 0x3D3D3A)
        /// The fill of a ticked Spread cell, and nothing else.
        static let accent = NSColor(hex: 0xC15F3C)
        static let successStrong = NSColor(hex: 0x15803D)
        static let warningStrong = NSColor(hex: 0xB45309)
        static let dangerStrong = NSColor(hex: 0xB91C1C)

        /// Replaces System Settings › Accessibility › Display › Increase Contrast, for a test.
        static var increaseContrastOverride: Bool?

        /// Read at draw time, so a drawing site can't forget the rule; the window redraws when it changes.
        static var increaseContrast: Bool {
            increaseContrastOverride ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
