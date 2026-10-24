import AppKit

/// What the first-launch card says, as a value so a test can check the copy against the real
/// shortcut. The folder is always the default one: the card describes what a stranger gets, so a
/// forced welcome in a scratch run is a faithful screenshot.
struct WelcomeCopy: Equatable {
    let title = "Welcome to Ideator"
    let buttonTitle = "Continue"
    /// The user's current shortcut (`HotKey.shortcut`), never a literal.
    var shortcut: Shortcut
    /// False when `HotKey` couldn't register it: the card must not promise a key that does nothing.
    var shortcutWorks: Bool
    var folder: URL = Library.defaultFolder

    struct Paragraph: Equatable {
        let lead: String
        let text: String
    }

    /// Four paragraphs, in this order: where the app is, the shortcut, where notes go, summaries.
    var paragraphs: [Paragraph] {
        let path = (folder.path as NSString).abbreviatingWithTildeInPath
        let hideAndShow = shortcutWorks
            ? "Press \(shortcut.display) from any app. Change it in Settings."
            : "Ideator couldn't claim \(shortcut.display), so there is no shortcut yet. Choose one in Settings."
        return [
            Paragraph(lead: "Find it in the menu bar.",
                      text: "Ideator has no Dock icon. Look for the stacked-rectangles icon at the top right of the menu bar. "
                          + "If your menu bar is crowded, the notch can hide it: the ⋯ button on the stack's ribbon "
                          + "(the card that appears next) has Settings and Quit too."),
            Paragraph(lead: "Hide and show your cards.", text: hideAndShow),
            Paragraph(lead: "Your notes are files.",
                      text: "Each card is a Markdown file in \(path). After you continue, macOS asks whether Ideator may "
                          + "use your Documents folder. Choose Allow."),
            Paragraph(lead: "Summaries are optional.",
                      text: "To show a short summary when you collapse a card, add your own Anthropic API key in Settings. "
                          + "Only a card's text goes to Anthropic. Nothing else leaves your Mac."),
        ]
    }
}

/// The first-launch card: borderless, on the same glass as a card and the stack (`configureAsCard`),
/// no ribbon, the app icon and a title in the card header font, four paragraphs and one pill
/// button. It shows no desk and sends no `Command`: the app has not loaded anything yet, and it
/// owns no state.
final class WelcomeWindow: NSWindow {
    private let welcomeView: WelcomeView
    var continueButton: NSButton { welcomeView.continueButton }

    /// `onContinue` runs for the button and for Return. It may run twice; the caller's launch
    /// order (`Launch.run`) makes that harmless.
    init(copy: WelcomeCopy, onContinue: @escaping () -> Void) {
        welcomeView = WelcomeView(copy: copy, onContinue: onContinue)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        configureAsCard(self, content: welcomeView)
        title = copy.title   // a borderless window never draws it; Mission Control and VoiceOver read it
    }

    /// Borderless windows refuse key status; Return must reach the button.
    override var canBecomeKey: Bool { true }

    /// Sizes the card to `width` points wide and as tall as its copy needs. Wrapping labels know
    /// their height only once they know their width, so the width goes in first and the height
    /// is read back after a layout pass.
    @discardableResult
    func fit(width: CGFloat) -> NSSize {
        setContentSize(NSSize(width: width, height: 100))
        welcomeView.layoutSubtreeIfNeeded()
        let size = NSSize(width: width, height: welcomeView.fittingHeight)
        setContentSize(size)
        return size
    }

    /// Puts the card top-right under the menu bar, in the stack's home cell, which is where the
    /// stack appears after Continue. As wide as that cell (at least 320 points), as tall as the
    /// copy needs, which is more than a cell's height.
    func present() {
        let cell = Grid(screen: NSScreen.screens.first)?.frame(of: Slot.stackHome)
            ?? NSRect(x: 100, y: 100, width: 342, height: 267)
        let size = fit(width: max(cell.width, 320))
        setFrameOrigin(NSPoint(x: cell.maxX - size.width, y: cell.maxY - size.height))
        bringForward()
    }

    /// The menu bar icon, the shortcut and opening the app again all land here while the card is up.
    func bringForward() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

/// Root view: draws the card (`CardShape.fillGlass`, `strokeEdge`, as `CardView.draw` does for a
/// popped card) and lays out the copy with Palette colors and the editor's fonts.
private final class WelcomeView: NSView {
    let continueButton: ActionButton
    private let stack = NSStackView()
    private var labels: [NSTextField] = []
    private let insets = NSEdgeInsets(top: CardShape.gap + CardView.margin.height + 4,
                                      left: CardShape.gap + CardView.margin.width,
                                      bottom: CardShape.gap + CardView.margin.height,
                                      right: CardShape.gap + CardView.margin.width)

    init(copy: WelcomeCopy, onContinue: @escaping () -> Void) {
        continueButton = ActionButton(title: copy.buttonTitle, help: "Continue to your cards") { onContinue() }
        super.init(frame: .zero)

        let icon = NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: copy.title)
        title.font = EditorStyle.header
        title.textColor = Palette.ink
        let header = NSStackView(views: [icon, title])
        header.spacing = 8
        header.alignment = .centerY
        stack.addArrangedSubview(header)

        for paragraph in copy.paragraphs {
            let label = NSTextField(wrappingLabelWithString: "")
            let text = NSMutableAttributedString(string: paragraph.lead + " ", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: Palette.ink])
            text.append(NSAttributedString(string: paragraph.text, attributes: [
                .font: EditorStyle.body, .foregroundColor: Palette.ink]))
            label.attributedStringValue = text
            labels.append(label)
            stack.addArrangedSubview(label)
        }

        continueButton.font = .systemFont(ofSize: 13, weight: .semibold)
        continueButton.contentTintColor = Palette.ribbonInk
        continueButton.keyEquivalent = "\r"
        continueButton.wantsLayer = true
        continueButton.layer?.backgroundColor = Palette.ribbon.cgColor
        continueButton.layer?.cornerRadius = 8
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [NSView(), continueButton])
        stack.addArrangedSubview(row)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: labels[labels.count - 1])
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            continueButton.widthAnchor.constraint(equalToConstant: 96),
            continueButton.heightAnchor.constraint(equalToConstant: 28),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ] + labels.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The height the stack needs at the width the view has now.
    var fittingHeight: CGFloat { ceil(stack.fittingSize.height + insets.top + insets.bottom) }

    override func layout() {
        for label in labels { label.preferredMaxLayoutWidth = bounds.width - insets.left - insets.right }
        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        CardShape.fillGlass(in: bounds, lineWidth: 1)
        CardShape.strokeEdge(in: bounds, lineWidth: 1, editing: false)
        window?.invalidateShadow()
    }
}
