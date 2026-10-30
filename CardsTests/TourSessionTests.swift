import XCTest
import Carbon.HIToolbox
@testable import Ideator

/// What the session does with the app: it listens, looks, draws through a screen and hands over to
/// the welcome and Finder. A recording screen and closure sources stand in for both.
final class TourSessionTests: XCTestCase {
    private typealias Fixtures = TourDeskFixtures

    private final class RecordingScreen: TourScreen {
        var onInput: (TourInput) -> Void = { _ in }
        var shown: [(scene: TourScene, takesKey: Bool)] = []
        var sizes: [(title: String, faceWidth: CGFloat)] = []
        weak var log: Harness?

        func size(of card: HintCard, faceWidth: CGFloat) -> CGSize {
            sizes.append((card.title.spoken, faceWidth))
            return CGSize(width: faceWidth + 6, height: 120)
        }

        func show(_ scene: TourScene, takesKey: Bool) { shown.append((scene, takesKey)) }
        func hide() { log?.steps.append("hide") }
    }

    /// The app, as the session sees it: a desk the test changes, and everything the session did to it.
    private final class Harness {
        var desk = Fixtures.desk(stack: ["s"])
        var visibility = Visibility.all
        var cells = SpreadCells.standard
        var shortcut = Fixtures.shortcut
        var active = true
        var stackRect = CGRect(x: 1000, y: 600, width: 322, height: 300)

        var steps: [String] = []
        var held: [CardID?] = []
        var measured: [Measure] = []
        var watchers = 0
        var stopped = 0
        var folders = 0
        var welcomes = 0
        var send: ((TourInput) -> Void)?

        let screen = RecordingScreen()
        private(set) var session: TourSession!

        init() {
            screen.log = self
            let pointer: TourSession.Pointer = { _, _, measure, panel in
                let size = panel(316)
                let stack = measure(.stack) ?? .zero
                return Pointing(panel: CGRect(x: stack.minX - size.width, y: stack.maxY - size.height,
                                              width: size.width, height: size.height),
                                notch: nil, rings: [], lit: [], needsMenuBarLevel: false)
            }
            let sources = TourSources(
                world: { [unowned self] in Fixtures.world(desk, visibility: visibility, shortcut: shortcut, cells: cells) },
                measure: { [unowned self] measure in
                    measured.append(measure)
                    return measure == .stack ? stackRect : nil
                },
                holdHover: { [unowned self] in held.append($0) },
                isActive: { [unowned self] in active },
                watch: { [unowned self] send in
                    watchers += 1
                    self.send = send
                    return { [unowned self] in stopped += 1 }
                },
                openNotesFolder: { [unowned self] in folders += 1; steps.append("folder") },
                backToWelcome: { [unowned self] in welcomes += 1; steps.append("welcome") })
            session = TourSession(sources: sources, screen: screen, pointer: pointer)
        }

        var scenes: [TourScene] { screen.shown.map(\.scene) }
        var title: String? { screen.shown.last?.scene.card.title.spoken }

        /// The reader acts on the desk and the controller tells the session it settled.
        func act(_ command: Command) {
            _ = desk.apply(command)
            send?(.deskSettled)
        }

        func hideAll() { visibility = .hideAll; send?(.deskSettled) }
        func showAll() { visibility = .all; send?(.deskSettled) }

        var reader: CardID? { Fixtures.world(desk).readerCard }

        func toPage3() {
            session.start(.firstPage)
            session.receive(.next)
            act(.new(at: Fixtures.now))
            session.receive(.next)
        }

        func toPage4() {
            toPage3()
            hideAll()
            showAll()
            session.receive(.next)
        }

        func toPage5() {
            toPage4()
            act(.returnToStack(reader!))
            session.receive(.next)
        }
    }

    // MARK: Starting

    func testNothingHappensBeforeTheFirstStart() {
        let app = Harness()

        app.session.receive(.next)
        app.session.receive(.deskSettled)
        app.session.receive(.happened(.space))

        XCTAssertEqual(app.watchers, 0, "a desk with no tour costs nothing")
        XCTAssertTrue(app.screen.shown.isEmpty)
        XCTAssertFalse(app.session.isRunning)
    }

    func testStartingShowsPageOneSubscribesOnceAndRestartingChangesNothing() {
        let app = Harness()

        app.session.start(.firstPage)
        XCTAssertEqual(app.title, "The stack holds your cards")
        XCTAssertEqual(app.scenes.last?.card.progress, "1 of 9")
        XCTAssertEqual(app.watchers, 1)

        app.session.start(.firstPage)
        XCTAssertEqual(app.watchers, 1, "one subscription for the whole tour")
        XCTAssertEqual(app.screen.shown.count, 1, "the same scene is not shown twice")
    }

    func testABackgroundStartShowsTheLastPage() {
        let app = Harness()

        app.session.start(.lastPage)

        XCTAssertEqual(app.title, "Done: replay from the menu bar")
        XCTAssertEqual(app.scenes.last?.card.footer, .backAndStartUsing)
    }

    func testThePanelsButtonsReachTheSession() {
        let app = Harness()
        app.session.start(.firstPage)

        app.screen.onInput(.next)

        XCTAssertEqual(app.title, "Click New on the stack")
    }

    // MARK: Looking

    func testAnUnchangedDeskShowsNothingNew() {
        let app = Harness()
        app.session.start(.firstPage)

        for _ in 1...3 { app.send?(.deskSettled) }

        XCTAssertEqual(app.screen.shown.count, 1, "a keystroke that moved nothing costs a look and a comparison")
    }

    func testTheDesksOwnNewCardAdvancesThePageWaitingForIt() {
        let app = Harness()
        app.session.start(.firstPage)
        app.session.receive(.next)
        XCTAssertEqual(app.title, "Click New on the stack")

        app.act(.new(at: Fixtures.now))

        XCTAssertEqual(app.title, "Type or paste into your card")
    }

    func testEverySceneIsReadFromTheWorldAtThatMoment() {
        let app = Harness()
        app.toPage3()
        XCTAssertTrue(app.scenes.last!.card.body.spoken.hasSuffix("⌃⌥I does the same from any app."))

        app.shortcut = ShortcutReading(display: "⌃⌥K", works: false)
        app.send?(.deskSettled)

        XCTAssertTrue(app.scenes.last!.card.body.spoken.hasSuffix("Ideator couldn't claim ⌃⌥K, so there is no shortcut yet; choose one in Settings."),
                      "Settings changes the shortcut with no notification, so the next look reads it again")
    }

    func testThePanelFollowsAStackThatMovesWhileTheDeskStandsStill() {
        let app = Harness()
        app.session.start(.firstPage)
        let before = app.scenes.last!.pointing.panel

        app.stackRect = app.stackRect.offsetBy(dx: -200, dy: -100)
        app.send?(.deskSettled)

        XCTAssertEqual(app.screen.shown.count, 2)
        XCTAssertEqual(app.scenes.last!.pointing.panel, before.offsetBy(dx: -200, dy: -100), "every drag step is a look")
    }

    func testThePanelSizeIsAskedOfTheScreenAtTheLayoutsWidth() {
        let app = Harness()
        app.session.start(.firstPage)

        XCTAssertEqual(app.screen.sizes.map(\.title), ["The stack holds your cards"])
        XCTAssertEqual(app.screen.sizes.first?.faceWidth, 316)
        XCTAssertEqual(app.scenes.last?.pointing.panel.size, CGSize(width: 322, height: 120))
    }

    func testPage5AnswersTheSystemsEventsThroughTheWatcher() {
        let app = Harness()
        app.toPage5()
        XCTAssertEqual(app.title, "Your cards follow you")

        app.send?(.happened(.space))
        XCTAssertEqual(app.title, "Still here on this Space")

        app.send?(.happened(.appFront))
        XCTAssertEqual(app.title, "Click any card to come forward")

        app.send?(.happened(.cardsFront))
        XCTAssertEqual(app.title, "Back in front")
    }

    // MARK: Page 4's hover buttons

    func testPage4HoldsTheReadersCardsHoverButtonsOnlyWhileItAsks() {
        let app = Harness()
        app.toPage4()
        let reader = app.reader
        XCTAssertNotNil(reader)
        XCTAssertEqual(app.held, [reader], "held once, however many looks follow")
        XCTAssertEqual(app.scenes.last?.heldHover, reader)

        app.send?(.deskSettled)
        XCTAssertEqual(app.held, [reader])

        app.act(.returnToStack(reader!))
        XCTAssertEqual(app.held, [reader, nil], "released the moment the page stops asking")
        XCTAssertNil(app.scenes.last?.heldHover)
    }

    func testEndingTheTourReleasesAHeldHoverAndStopsListening() {
        let app = Harness()
        app.toPage4()
        let reader = app.reader

        app.session.receive(.back)   // page 3: the hover is released by the next look
        XCTAssertEqual(app.held, [reader, nil])

        app.session.receive(.skip)
        app.session.receive(.finish)

        XCTAssertEqual(app.stopped, 1, "the subscription ends with the tour")
        XCTAssertFalse(app.session.isRunning)
        let shown = app.screen.shown.count
        app.send?(.deskSettled)
        app.session.receive(.next)
        XCTAssertEqual(app.screen.shown.count, shown, "nothing draws after the end")
    }

    // MARK: Leaving

    func testBackFromPage1OrdersThePanelOutBeforeTheWelcomeComes() {
        let app = Harness()
        app.session.start(.firstPage)

        app.session.receive(.back)

        XCTAssertEqual(app.steps, ["hide", "welcome"], "two Skip the tour buttons must never be on screen at once")
        XCTAssertEqual(app.stopped, 1)
        XCTAssertEqual(app.welcomes, 1)
        XCTAssertFalse(app.session.isRunning)
    }

    func testStartingAgainAfterTheWelcomeSubscribesAgain() {
        let app = Harness()
        app.session.start(.firstPage)
        app.session.receive(.back)

        app.session.start(.firstPage)

        XCTAssertEqual(app.watchers, 2)
        XCTAssertEqual(app.title, "The stack holds your cards")
        XCTAssertTrue(app.session.isRunning)
    }

    func testPage9sButtonOpensTheNotesFolderAfterTheTourIsOutOfTheWay() {
        let app = Harness()
        app.session.start(.lastPage)

        app.session.receive(.finish)

        XCTAssertEqual(app.steps, ["hide", "folder"])
        XCTAssertEqual(app.folders, 1)
        XCTAssertFalse(app.session.isRunning)
    }

    func testSkipGoesStraightToPage9() {
        let app = Harness()
        app.toPage3()

        app.session.receive(.skip)

        XCTAssertEqual(app.title, "Done: replay from the menu bar")
        XCTAssertEqual(app.scenes.last?.card.canSkip, false)
    }

    // MARK: Who gets the keyboard

    func testPage9TakesKeyOnceAndOnlyWhileIdeatorIsActive() {
        let app = Harness()
        app.active = false
        app.session.start(.lastPage)
        XCTAssertEqual(app.screen.shown.map(\.takesKey), [false], "a start by the AI tool's helper leaves a Return where it was typed")

        app.active = true
        app.stackRect = app.stackRect.offsetBy(dx: -10, dy: 0)
        app.send?(.deskSettled)
        XCTAssertEqual(app.screen.shown.map(\.takesKey), [false, true], "the reader clicked a card: now Return presses the button")

        app.stackRect = app.stackRect.offsetBy(dx: -10, dy: 0)
        app.send?(.deskSettled)
        XCTAssertEqual(app.screen.shown.map(\.takesKey), [false, true, false], "once per showing: a drag does not take the keyboard again")

        app.session.receive(.back)
        app.session.receive(.next)
        XCTAssertEqual(app.screen.shown.last?.takesKey, true, "a new showing of page 9 may take it again")
    }

    func testNoOtherPageTakesKey() {
        let app = Harness()
        app.toPage5()
        app.session.receive(.skip)
        app.session.receive(.back)
        app.session.receive(.back)

        let others = app.screen.shown.filter { $0.scene.card.progress != "9 of 9" }
        XCTAssertFalse(others.isEmpty)
        XCTAssertTrue(others.allSatisfy { !$0.takesKey }, "only Return on page 9 needs the keyboard")
    }
}

/// The real sources over a real controller: what the tour is allowed to look at, and how it hears.
final class TourSourcesTests: XCTestCase {
    private var folder: URL!
    private var windowsBefore: [NSWindow] = []
    private var controllers: [DeskController] = []
    private let suites = TestDefaults()

    override func setUpWithError() throws {
        windowsBefore = NSApp.windows
        folder = FileManager.default.temporaryDirectory
            .appending(path: "CardsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# Groceries\n".utf8).write(to: folder.appending(path: "card.md"))
    }

    override func tearDown() async throws {
        for window in NSApp.windows where !windowsBefore.contains(window) {
            window.orderOut(nil)
            window.close()
        }
        let left = NSApp.windows.filter { $0.isVisible && !windowsBefore.contains($0) }
        XCTAssertEqual(left.map(\.className), [], "a window left on screen sends a click to a controller that is gone")
        controllers = []
        suites.removeAll()
        try? FileManager.default.removeItem(at: folder)
    }

    private struct Rig {
        var controller: DeskController
        var sources: TourSources
        var hotKey: HotKey
    }

    private func makeRig() -> Rig {
        let controller = DeskController(library: Library(folder: folder), keys: KeyStore(inKeychain: false),
                                        appMenu: { NSMenu() }, pointer: { NSPoint(x: -10_000, y: -10_000) }, beep: {})
        controllers.append(controller)
        let preferences = Preferences(defaults: suites.make())
        let hotKey = HotKey(preferences: preferences, action: {})
        let sources = TourSources.live(controller: controller, hotKey: hotKey, spread: SpreadChoice(preferences: preferences),
                                       statusItem: nil, notesFolder: folder, backToWelcome: {})
        return Rig(controller: controller, sources: sources, hotKey: hotKey)
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testTheWorldIsTheControllersDeskAndTheAppsOwnShortcutAndCells() async {
        let rig = makeRig()
        let world = rig.sources.world()

        XCTAssertEqual(world.desk, rig.controller.desk)
        XCTAssertEqual(world.grid, rig.controller.grid)
        XCTAssertEqual(world.visibility, .all)
        XCTAssertEqual(world.shortcut, ShortcutReading(display: Shortcut.standard.display, works: true),
                       "works is HotKey.problem == nil, as the welcome reads it")
        XCTAssertEqual(world.spreadCells, .standard)

        rig.controller.send(.new(at: Date()))
        rig.controller.setHidden(true)
        let later = rig.sources.world()
        XCTAssertEqual(later.desk.popped.count, 1)
        XCTAssertEqual(later.visibility, .hideAll)
    }

    func testTheShortcutDoesNotWorkWhenTheHotKeyCouldNotClaimIt() async {
        let rig = makeRig()
        let combination = Shortcut(keyCode: UInt32(kVK_F16), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))!
        func hotKey() -> HotKey {
            let preferences = Preferences(defaults: suites.make())
            preferences.shortcut = combination
            return HotKey(preferences: preferences, action: {})
        }
        let holder = hotKey()
        let loser = hotKey()
        holder.register()
        loser.register()
        XCTAssertEqual(loser.problem, .taken, "sanity: a second claim on one combination fails")
        let sources = TourSources.live(controller: rig.controller, hotKey: loser,
                                       spread: SpreadChoice(preferences: Preferences(defaults: nil)),
                                       statusItem: nil, notesFolder: folder, backToWelcome: {})

        XCTAssertEqual(sources.world().shortcut, ShortcutReading(display: "⌃⌥⇧⌘F16", works: false))
    }

    func testMeasuresAnswerFromTheLiveWindowsAndAreNilWhereNothingIsOnScreen() async {
        let rig = makeRig()
        let controller = rig.controller
        controller.send(.new(at: Date()))
        let id = controller.desk.popped[0].card.id

        XCTAssertEqual(rig.sources.measure(.stack), controller.grid.frame(of: controller.desk.stackPlace))
        XCTAssertEqual(rig.sources.measure(.card(id)), controller.grid.frame(of: controller.desk.popped[0].place))
        XCTAssertNil(rig.sources.measure(.card(CardID(rawValue: "missing"))))
        XCTAssertNil(rig.sources.measure(.menuBarIcon), "no status item, no icon")

        let new = rig.sources.measure(.control(.new))
        XCTAssertNotNil(new)
        XCTAssertTrue(controller.stackFrame.contains(new!), "a ribbon button is inside the stack")
        let hover = rig.sources.measure(.hoverCorner(id))
        XCTAssertNotNil(hover)
        XCTAssertTrue(rig.sources.measure(.card(id))!.contains(hover!), "the hover row is inside its card")

        controller.setHidden(true)
        XCTAssertEqual(rig.sources.measure(.stack), StackWindow.ribbonOnlyFrame(in: controller.grid.frame(of: controller.desk.stackPlace)),
                       "under Hide all the stack is its ribbon")
        XCTAssertNil(rig.sources.measure(.hoverCorner(id)), "the card's window is ordered out")
        XCTAssertNotNil(rig.sources.measure(.card(id)), "where it would be")
    }

    func testHoldingAHoverReachesTheControllerAndReleasing() async {
        let rig = makeRig()
        rig.controller.send(.new(at: Date()))
        let id = rig.controller.desk.popped[0].card.id

        rig.sources.holdHover(id)
        XCTAssertEqual(rig.controller.heldHover, id)

        rig.sources.holdHover(nil)
        XCTAssertNil(rig.controller.heldHover)
    }

    func testWatchHearsEverySettleAndTheThreeNotificationsAndStopsWhenTold() async {
        let rig = makeRig()
        var heard: [TourInput] = []

        let stop = rig.sources.watch { heard.append($0) }
        rig.controller.setHidden(true)
        XCTAssertTrue(heard.contains(.deskSettled), "Hide all is not a Command, but it settles")

        heard = []
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        await eventually { heard.contains(.happened(.cardsFront)) }
        XCTAssertTrue(heard.contains(.happened(.space)), "a swipe to another Space")
        XCTAssertTrue(heard.contains(.happened(.appFront)), "Ideator resigned: another app is in front")
        XCTAssertTrue(heard.contains(.happened(.cardsFront)), "Ideator became active again")

        heard = []
        stop()
        rig.controller.setHidden(false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(heard, [], "nothing is heard after the tour ends")
        XCTAssertNil(rig.controller.onSettle)
    }

    func testEveryCommandIsALookBecauseEveryCommandRenders() async {
        let rig = makeRig()
        var looks = 0
        let stop = rig.sources.watch { _ in looks += 1 }
        defer { stop() }

        rig.controller.send(.new(at: Date()))

        XCTAssertGreaterThan(looks, 0)
    }
}
