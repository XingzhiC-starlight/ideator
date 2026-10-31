import AppKit

// Entry point and app-level wiring: menu bar item, global hotkey, app events.
// The build settings set LSUIElement = YES (menu bar app, no Dock icon).

@main
enum CardsApp {
    static func main() {
        let app = NSApplication.shared
        // The test bundle runs inside this app.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launch: Launch
    private let keys: KeyStore
    private lazy var preferences = launch.preferences(standard: .standard)
    private lazy var hotKey = HotKey(preferences: preferences) { [weak self] in
        self?.withDesk { $0.toggleHidden() }
    }
    private lazy var updates = Updates(build: .current, isScratch: launch.isScratch)
    private lazy var aiTools = AIToolsChoice(preferences: preferences)
    /// Settings writes it; the controller reads it at each Spread click.
    private lazy var spreadChoice = SpreadChoice(preferences: preferences)
    private let held = HeldCards()
    private var inbox: ToolInbox?
    private var terminationSource: DispatchSourceSignal?
    private var controller: DeskController?
    /// Whichever welcome is on screen, the first or the one Back from page 1 shows again.
    private var welcome: WelcomeWindow?
    /// Built right after the controller, so it exists exactly when there is a desk to tour.
    private var tour: TourSession?
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindow?

    override init() {
        launch = Launch(arguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
                        environment: ProcessInfo.processInfo.environment)
        keys = launch.keys()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        statusItem = makeStatusItem()
        // A scratch run leaves the global shortcut to the owner's running Ideator.
        if !launch.isScratch { hotKey.register() }
        // Before the welcome, so a helper that started this run reaches it; the cards wait for Continue.
        inbox = ToolInbox(endpoint: Endpoint(scratchFolder: launch.folder),
                          instruction: { [unowned self] in aiTools.value.instruction.text }) { [unowned self] request, reply in
            if let answer = answer(request.card) { reply(answer) } else { held.hold(request, reply: reply) }
        }
        terminationSource = inbox.map { Self.removeOnSIGTERM($0.file) }
        // Building the controller is the first touch of the notes folder, which starts macOS's
        // Documents prompt, so only `Launch.run` may do it: after the welcome, when one is due.
        // The tour starts after that, where the welcome's button sends it.
        launch.run(
            preferences: preferences,
            welcome: { [unowned self] kind, choose in showWelcome(kind, choose) },
            openNotes: { [unowned self] in
                let controller = DeskController(library: Library(folder: launch.notesFolder), keys: keys,
                                                appMenu: { [unowned self] in self.makeAppMenu(for: .ribbon) },
                                                spreadCells: { [unowned self] in self.spreadChoice.cells })
                self.controller = controller
                held.release { self.answer($0) ?? .waitingForContinue }
                updates.start()
                tour = TourSession(sources: .live(controller: controller, hotKey: hotKey, spread: spreadChoice,
                                                  statusItem: statusItem, notesFolder: launch.notesFolder,
                                                  backToWelcome: { [unowned self] in showWelcomeAgain() }),
                                   screen: TourStage())
                if !launch.inBackground { NSApp.activate() }
            },
            startTour: { [unowned self] start in tour?.start(start) })
    }

    /// Nil while the notes are not open yet: the card waits for Continue.
    private func answer(_ card: AddCard) -> ToolReply? {
        guard aiTools.value.enabled else { return .turnedOff }
        return controller?.add(card, landing: aiTools.value.landing)
    }

    func applicationWillTerminate(_ notification: Notification) { inbox?.close() }

    /// `kill`, as cards-verify and package.sh end a scratch run, skips `applicationWillTerminate`, and
    /// each scratch folder's socket file has a name of its own, so none is ever reused. Off the main
    /// thread, so a blocked main thread never delays the kill; the process then ends as SIGTERM ends it.
    private nonisolated static func removeOnSIGTERM(_ file: ToolInbox.File) -> DispatchSourceSignal {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        source.setEventHandler {
            file.remove()
            signal(SIGTERM, SIG_DFL)
            raise(SIGTERM)
        }
        source.resume()
        return source
    }

    /// The welcome. A button closes it first and calls `choose` on the next turn of the run loop: the
    /// Documents prompt blocks the main thread until it is answered, and the window must not sit
    /// frozen under it. With a desk already on screen (Back from page 1) it floats, so a click on a
    /// card, which raises the cards as a group, never buries it.
    private func showWelcome(_ kind: WelcomeKind, _ choose: @escaping (WelcomeChoice) -> Void) {
        let window = WelcomeWindow(copy: WelcomeCopy(), kind: kind) { [unowned self] choice in
            welcome?.close()
            welcome = nil
            DispatchQueue.main.async { choose(choice) }
        }
        welcome = window
        window.present(takingFocus: launch.welcomeTakesFocus, floating: controller != nil)
    }

    /// Back from page 1. Its buttons only start the tour: the notes are open already, so they never
    /// reach `openNotes` again, and the Documents prompt does not come twice.
    private func showWelcomeAgain() {
        showWelcome(.fullTour) { [unowned self] choice in
            if let start = WelcomeKind.fullTour.tourStart(after: choice) { tour?.start(start) }
        }
    }

    /// While any welcome is up, the shortcut, the menus and a reopen bring it forward instead of
    /// reaching the desk, which on Back from page 1 is already there.
    private func withDesk(_ action: (DeskController) -> Void) {
        if let welcome { welcome.bringForward() } else if let controller { action(controller) }
    }

    func applicationDidBecomeActive(_ notification: Notification) { controller?.appDidBecomeActive() }
    func applicationDidResignActive(_ notification: Notification) { controller?.flush() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.shouldQuit() ?? true ? .terminateNow : .terminateCancel
    }
    func applicationDidChangeScreenParameters(_ notification: Notification) { controller?.screensChanged() }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs shows everything and
    /// brings the app forward. Returning false skips the default, which has no window to open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        withDesk { $0.setHidden(false) }
        return false
    }

    /// Menu bar icon. A crowded menu bar can hide it behind the notch, so the stack's ribbon has
    /// Hide all as a button and a menu with the rest, Show the Tour included.
    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Ideator")
        item.menu = makeAppMenu(for: .menuBar)
        return item
    }

    private enum MenuSurface { case menuBar, ribbon }

    /// The app's menu. The ribbon's is New Spread, then Show the Tour, Settings… and Quit: Hide all
    /// and Spread are ribbon buttons, New Spread is Spread's Option-click in words, and Open stack
    /// means nothing on the stack. The menu bar icon's adds Show all / Hide all / Open stack above
    /// Show the Tour and Settings…, and Check for Updates… after them. Settings has Check Now for a
    /// Mac whose notch hides the icon.
    private func makeAppMenu(for surface: MenuSurface) -> NSMenu {
        let menu = NSMenu()
        if surface == .ribbon {
            menu.addItem(withTitle: "New Spread", action: #selector(newSpread), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        if surface == .menuBar {
            menu.addItem(withTitle: "Show All", action: #selector(showAll), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Hide All", action: #selector(hideAll), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Open Stack", action: #selector(openStack), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Show the Tour", action: #selector(showTour), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        if surface == .menuBar {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ideator", action: #selector(quit), keyEquivalent: "").target = self
        return menu
    }

    /// Never shown (accessory apps have no menu bar), but key equivalents still route through it:
    /// Edit (Undo, Redo, Cut, Copy, Paste, Select All) and Format (Bold ⌘B, Italic ⌘I), all
    /// targeting the first responder.
    private func installMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(withTitle: "Quit Ideator", action: #selector(quit), keyEquivalent: "q").target = self

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let format = NSMenu(title: "Format")
        format.addItem(withTitle: "Bold", action: #selector(CardTextView.cardsToggleBold(_:)), keyEquivalent: "b")
        format.addItem(withTitle: "Italic", action: #selector(CardTextView.cardsToggleItalic(_:)), keyEquivalent: "i")

        for submenu in [app, edit, format] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    @objc private func showAll() { withDesk { $0.setHidden(false) } }
    @objc private func hideAll() { withDesk { $0.setHidden(true) } }
    @objc private func openStack() { withDesk { $0.openStack() } }
    @objc private func newSpread() { withDesk { $0.spread(fresh: true) } }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func checkForUpdates() { updates.checkNow() }

    /// Replays the tour from page 1 with no welcome and no prompt. Page 1 describes the stack's card,
    /// so it first shows everything; the tour itself never touches the desk. Starting a running
    /// tour again restarts it.
    @objc private func showTour() {
        guard welcome == nil, let controller, let tour else { return }
        controller.setHidden(false)
        tour.start(.firstPage)
    }

    /// The stack's cell is read on every refresh: the window is kept between openings, the stack
    /// moves while it is closed, and before Continue there is no desk.
    @objc private func openSettings() {
        let window = settingsWindow ?? SettingsWindow(keys: keys, hotKey: hotKey, updates: updates, aiTools: aiTools,
                                                      connect: HelperCommand(app: Bundle.main.bundleURL, scratchFolder: launch.folder),
                                                      spread: spreadChoice,
                                                      stackCell: { [weak self] in self?.controller?.desk.stackPlace.slot ?? Slot.stackHome }) { [weak self] in
            self?.controller?.apiKeyChanged()
        }
        settingsWindow = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates):
            menuItem.title = updates.menuTitle
            return updates.canCheck
        case #selector(showTour):
            // No desk to tour before the notes open, and the welcome has the reader's attention.
            return tour != nil && welcome == nil
        default:
            return true
        }
    }
}
