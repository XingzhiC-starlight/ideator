import AppKit

/// The single owner of state and of every window.
///
/// Views and background work never change anything themselves: they `send` a `Command`. The
/// controller applies it to the `Desk`, then derives everything else from the new desk: window
/// frames and contents (`render`), the folder (`Library.save`, debounced) and summary requests
/// (`Summarizer.sync`). None of those is told *what* changed. Each compares the desk with the
/// world and fixes the difference, so each is safe to run any number of times.
final class DeskController {
    private(set) var desk: Desk
    private var grid: Grid
    /// What "Hide all" / ⌥⌘C has hidden. Presentation only: not part of the desk, not persisted.
    private var visibility = Visibility.all
    /// One window per popped card, created on pop and closed when the card leaves the desktop.
    private var cardWindows: [CardID: CardWindow] = [:]
    private lazy var stackWindow = StackWindow(send: { [unowned self] in self.send($0) }, menu: appMenu,
                                               toggleHidden: { [unowned self] in self.toggleHidden() },
                                               drag: windowDrag(.stack))
    /// The outline of the slot a drag would snap to; visible only while something is dragged.
    private let guide = SlotGuide()
    private lazy var summarizer = Summarizer(
        apiKey: { [unowned self] in self.keys.apiKey },
        deliver: { [unowned self] id, summary in self.send(.storeSummary(id, summary)) })
    private let library: Library
    private let keys: KeyStore
    /// The app's menu (Settings…, Quit) for the stack's ribbon button.
    private let appMenu: () -> NSMenu
    private var pendingSave: Task<Void, Never>?
    private var saveFailing = false
    private var pointerMonitors: [Any] = []

    init(library: Library, keys: KeyStore, appMenu: @escaping () -> NSMenu) {
        self.library = library
        self.keys = keys
        self.appMenu = appMenu
        desk = library.load()
        grid = Self.currentGrid() ?? Grid(area: CGRect(x: 0, y: 0, width: 1512, height: 949))
        summarizer.sync(desk.allCards, typing: nil)
        render()
        trackPointer()
    }

    // MARK: The one way state changes

    func send(_ command: Command) {
        // Popping the card being edited on the stack moves the cursor with it.
        let carriedSelection: NSRange? = if case .pop = command { stackWindow.editingSelection } else { nil }
        let arrived = desk.apply(command)
        let desktopFull = arrived == nil && desk.firstFreeSlot == nil
        visibility.reveal(after: command, arrived: arrived, in: desk)
        let typing: CardID? = if case .writeBlank = command { desk.selectedCard?.id } else { command.typedCard }
        scheduleSave()
        summarizer.sync(desk.allCards, typing: typing)
        render()
        switch command {
        case .new:
            if let arrived {
                cardWindows[arrived]?.focusEditor()
            } else if desktopFull {
                NSSound.beep()   // "Desktop full"
                stackWindow.focusEditor()
            }
        case .pop:
            if let arrived, let carriedSelection {
                cardWindows[arrived]?.focusEditor(range: carriedSelection)
            } else if desktopFull {
                NSSound.beep()
            }
        default:
            break
        }
    }

    // MARK: Menu bar, hotkey, app events

    func setHidden(_ hide: Bool) {
        visibility = hide ? .hideAll : .all
        render()
        if !hide {
            NSApp.activate()
            raiseGroup()
        }
    }

    /// ⌥⌘C, and the stack ribbon's Hide all / Show all button.
    func toggleHidden() { setHidden(!visibility.isHidden) }

    func openStack() {
        setHidden(false)
        stackWindow.makeKeyAndOrderFront(nil)
    }

    /// `applicationDidBecomeActive`: the user clicked a card (or used the hotkey or menu).
    /// Raises the whole group, then picks up outside changes to the folder.
    func appDidBecomeActive() {
        raiseGroup()
        // A rescan after a failed save would replace the unsaved edits with the stale files.
        guard flush() else { return }
        if let notes = library.rescan() { send(.syncFiles(notes)) }
    }

    /// `applicationDidChangeScreenParameters`: new geometry, same places. Snapped cards re-snap
    /// and free ones keep their fraction of the screen.
    func screensChanged() {
        grid = Self.currentGrid() ?? grid
        render()
    }

    /// Settings saved or removed the key.
    func apiKeyChanged() { send(.forgetFailedSummaries) }

    /// Save now: on deactivate, quit, and before a rescan. False when the folder doesn't match the desk.
    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        return saveNow()
    }

    // MARK: Derived side effects

    /// Reconciles every window with the desk. Compares against the windows' real state, not
    /// against the previous desk, so it also undoes UI drift: a card dropped back near its own
    /// slot (no model change) still snaps home.
    private func render() {
        let popped = desk.cardFaces(hasKey: keys.apiKey != nil)
        let live = Set(popped.map(\.face.id))
        for (id, window) in cardWindows where !live.contains(id) {
            window.orderOut(nil)
            window.close()
            cardWindows[id] = nil
        }
        for (place, face) in popped {
            let window = cardWindows[face.id] ?? makeCardWindow(face.id)
            window.apply(face, frame: grid.frame(of: place))
            setVisible(window, visibility.shows(face.id))
        }
        stackWindow.apply(desk.stackFace(hasKey: keys.apiKey != nil), cell: grid.frame(of: desk.stackPlace),
                          visibility: visibility)
        setVisible(stackWindow, true)   // Hide all keeps the ribbon
    }

    private func setVisible(_ window: NSWindow, _ visible: Bool) {
        if !visible {
            window.orderOut(nil)
        } else if !window.isVisible {
            window.orderFront(nil)   // only newly shown windows: never reshuffle the z-order
        }
    }

    private func makeCardWindow(_ id: CardID) -> CardWindow {
        let window = CardWindow(id: id, send: { [unowned self] in self.send($0) }, drag: windowDrag(.card(id)))
        cardWindows[id] = window
        return window
    }

    /// A drag of `item`'s window: the guide follows it, and the drop asks `Place.dropped(at:)`,
    /// the same rule the guide shows, where it lands. A drop that changes nothing still renders,
    /// which puts the window back on its place.
    private func windowDrag(_ item: Movable) -> WindowDrag {
        WindowDrag(
            moved: { [unowned self] frame in
                let target = Place.guide(at: center(of: frame))
                guide.show(grid.frame(of: target.slot), snaps: target.snaps)
            },
            dropped: { [unowned self] frame in
                guide.hide()
                send(.move(item, to: Place.dropped(at: center(of: frame))))
            })
    }

    /// Where a dragged window's center counts as being: past the limit `Grid` sets, at the limit,
    /// which is where the drop then lands the window.
    private func center(of frame: CGRect) -> GridPoint {
        grid.point(at: CGPoint(x: frame.midX, y: frame.midY))
    }

    /// macOS brings forward only the clicked window when an app activates. Cards are one group,
    /// so order the stack and every visible card front, back to front so overlapping cards keep
    /// their order, then the key window last so it stays on top. Another app's click needs no
    /// code: its window simply comes in front of ours.
    private func raiseGroup() {
        let frontToBack = NSWindow.windowNumbers(options: [.allSpaces]) ?? []
        let depth = Dictionary(frontToBack.enumerated().map { ($1.intValue, $0) }, uniquingKeysWith: min)
        let group: [NSWindow] = [stackWindow] + Array(cardWindows.values)
        for window in group.filter(\.isVisible).sorted(by: { depth[$0.windowNumber, default: .max] > depth[$1.windowNumber, default: .max] }) {
            window.orderFront(nil)
        }
        NSApp.keyWindow?.orderFront(nil)
    }

    /// Hover follows the pointer's real position, not per-view enter/exit events: a fast pointer
    /// can skip a window's exit event, which would leave its hover buttons showing. A global
    /// monitor sees moves while another app is active, a local one while Ideator is; watching the
    /// mouse needs no special permission.
    private func trackPointer() {
        let moved: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved) {
            pointerMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { moved($0); return $0 }) {
            pointerMonitors.append(monitor)
        }
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        for window in cardWindows.values { window.pointerMoved(to: location) }
        stackWindow.pointerMoved(to: location)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            _ = self.saveNow()
        }
    }

    private func saveNow() -> Bool {
        let saved = library.save(desk)
        let firstFailure = !saved && !saveFailing
        saveFailing = !saved   // before the alert: its modal loop can deliver another save
        if firstFailure {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Ideator can't save your notes"
            alert.informativeText = "Ideator couldn't write to \(library.folder.path). "
                + "Your cards stay in memory until a save succeeds."
            NSApp.activate()
            alert.runModal()
        }
        return saved
    }

    /// The menu-bar screen.
    private static func currentGrid() -> Grid? {
        Grid(screen: NSScreen.screens.first)
    }
}
