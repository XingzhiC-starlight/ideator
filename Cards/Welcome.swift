import AppKit

struct WelcomeCopy: Equatable {
    /// Raise it whenever the paragraphs about Anthropic, OpenAI or GitHub change what they say
    /// Ideator sends or asks, so a Mac that acknowledged an older card sees this one before Ideator
    /// does anything the older card did not announce. 1 is the card from before the GitHub
    /// paragraph, 2 the card from before OpenAI was named.
    static let version = 3

    let title = "Welcome to Ideator"
    let buttonTitle = "Continue"
    var shortcut: Shortcut
    var shortcutWorks: Bool
    /// Always the default folder, even in a scratch run, so a forced welcome shows what a stranger sees.
    let folder = Library.defaultFolder

    struct Paragraph: Equatable {
        let lead: String
        let text: String
    }

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
                      text: "To show a short summary on each card when you turn on Clarity, add your own Anthropic or "
                          + "OpenAI API key in Settings. Ideator then sends a card's text to Anthropic or OpenAI, "
                          + "whichever your key is for, whenever the card has no summary for its text as it is now, such "
                          + "as when you save the key or change the card. Only a card's text goes to that company."),
            Paragraph(lead: "Updates come from GitHub.",
                      text: "Once a day Ideator asks GitHub whether a newer version exists, and it asks you before it "
                          + "installs one. You can turn the daily check off in Settings. Nothing else leaves your Mac."),
        ]
    }
}

final class WelcomeWindow: NSWindow {
    private let welcomeView: WelcomeView
    var continueButton: NSButton { welcomeView.continueButton }

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

    /// Top-right in the stack's home cell, where the stack appears after Continue. Without focus (a
    /// start by the AI tools helper) it shows in front but leaves the active app and its key window
    /// alone, so a Return typed in the AI tool never reaches Continue; a click on it takes focus.
    func present(takingFocus: Bool) {
        let cell = Grid(screen: NSScreen.screens.first)?.frame(of: Slot.stackHome)
            ?? NSRect(x: 100, y: 100, width: 342, height: 267)
        let size = fit(width: max(cell.width, 320))
        setFrameOrigin(NSPoint(x: cell.maxX - size.width, y: cell.maxY - size.height))
        if takingFocus { bringForward() } else { orderFrontRegardless() }
    }

    func bringForward() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

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

// MARK: Tour welcome copy (Core workstream; replaces WelcomeCopy, whose `version` stays the one record)

/// The welcome before the tour: the prototype's `#welcome` block, exact. The disclosures say what the
/// older card said Ideator sends or asks (GitHub once a day and asks before installing; a card's text
/// leaves only with your own key) in fewer words, so `WelcomeCopy.version` stays 3.
struct TourWelcomeCopy: Equatable {
    struct Paragraph: Equatable {
        let lead: String
        let text: String
    }

    let title = "Welcome to Ideator"
    let intro = "Every note is a small card on your screen. The tour takes two minutes on your real desk, "
        + "and nothing happens until you click."
    /// Always the default folder, even in a scratch run, so a forced welcome shows what a stranger sees.
    let folder = Library.defaultFolder
    let disclosures: [Paragraph]

    init() {
        let path = (Library.defaultFolder.path as NSString).abbreviatingWithTildeInPath
        disclosures = [
            Paragraph(lead: "Your notes are files.",
                      text: "Each card is a Markdown file in \(path). When you continue, macOS asks whether Ideator "
                          + "may use your Documents folder. Choose Allow."),
            Paragraph(lead: "Updates come from GitHub.",
                      text: "Once a day Ideator asks GitHub whether a newer version exists, and asks you before "
                          + "installing. Turn the check off in Settings."),
            Paragraph(lead: "AI is optional.",
                      text: "Summaries and cards from Claude Code need your own API key in Settings. Only then does "
                          + "a card's text leave your Mac."),
        ]
    }
}

// MARK: Tour welcome (UI workstream fills these in; replaces WelcomeWindow)

/// The welcome: 446 pt window (440 visible plus the gaps), centered, the card look with the tour's
/// tint. "Skip the tour" link and "Start the tour" for `.fullTour`; "Continue" alone otherwise.
final class TourWelcomeWindow: NSWindow {
    /// "Start the tour" (`.fullTour`) or "Continue": Return presses it.
    var defaultButton: NSButton { fatalError("not implemented") }
    /// "Skip the tour", an underlined link at the footer's left; nil unless `.fullTour`.
    var skipButton: NSButton? { fatalError("not implemented") }

    init(copy: TourWelcomeCopy, kind: WelcomeKind, choose: @escaping (WelcomeChoice) -> Void) {
        fatalError("not implemented")
    }

    override var canBecomeKey: Bool { true }

    @discardableResult
    func fit(width: CGFloat) -> NSSize { fatalError("not implemented") }

    /// Centered on the screen. `takingFocus: false` orders it front without making it key, as today.
    /// `floating`: the welcome shown again by Back from page 1 sits at the panel's level, so the
    /// cards' raise never buries it; at launch it is `.normal`.
    func present(takingFocus: Bool, floating: Bool) { fatalError("not implemented") }

    func bringForward() { fatalError("not implemented") }
}
