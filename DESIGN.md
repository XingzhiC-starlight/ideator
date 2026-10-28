# Ideator: design notes

How the prototype in [CARDS-SPEC.md](CARDS-SPEC.md) is put together, and why.

## Problem

Up to 19 card windows and a stack window are all views of one tightly coupled state. Pop, "↩
Stack", delete and the stack's swipes and edge bands all move through one stack loop, and the
card the stack shows is editable in place. Clarity has a global
switch plus a per-card "last state". Summaries arrive later and must attach to the right version
of the right card. All of it persists to Markdown plus one sidecar. The header is both the first
line of editable text and the handle you drag the card by.

## Usage (caller's view)

All state is one value, `Desk`. To change anything, a view sends a `Command`. Nothing saves,
renders or requests a summary itself: after every command the controller derives all three from
the new desk.

```swift
// A view reports intent (StackWindow, a two-finger swipe or a click in the right edge band):
send(.flipStack(.next))

// A rule, tested with plain values: no AppKit, no disk.
var desk = Desk(notes: notes, saved: SavedDesk(stack: [d, a, b, c]))
let shown = desk.apply(.pop)           // d → slot 0

// The controller: the whole side-effect story.
func send(_ command: Command) {
    let focus = desk.apply(command)
    scheduleSave()                     // Library.save(desk): writes only what differs on disk
    summarizer.sync(deskCards, ...)    // wanted requests = f(desk)
    render()                           // windows = f(desk, grid)
}
```

## Shape

| File | What it owns |
| --- | --- |
| `Desk.swift` | the state, `Command`, every rule (pop, flip, swap, clarity, restore), and Hide all's `Visibility` |
| `Grid.swift` | slots, free positions, the snap rule, the overhang limit, frames and edge bands (pure) |
| `Note.swift` | a card's content, its Markdown format, the typing rules for lists, and the level tidy-up |
| `Clipboard.swift` | copy and paste formats: a run of lines to and from Markdown text and HTML lists (pure) |
| `DeskController.swift` | the single owner of the desk and of every window |
| `Library.swift` | `~/Documents/Ideator/*.md` and the hidden sidecar `.cards.json` |
| `Summarizer.swift` | summary requests, `Provider` (whose key it is), and the two wire formats, `Anthropic` and `OpenAI` |
| `CardWindow.swift`, `CardEditor.swift` | the card window, press routing, and the text view |
| `StackWindow.swift`, `Swipe.swift` | the stack window and its count badge; the rules that turn scroll events into flips (pure) |
| `StackArranger.swift` | the popover off the badge that reorders the stack, and the `Arrangement` value it reads (see The stack arranger) |
| `HotKey.swift` | `Shortcut`, the legal global key combination, and `HotKey`, its one registration with Carbon: chosen shortcut, registered or not, and why not |
| `Launch.swift`, `Preferences.swift` | how the process was started (`-CardsFolder` makes a scratch run, which also picks the key store); the persisted shortcut, and no persistence at all in a scratch run |
| `Welcome.swift` | the first-launch card and its copy |
| `Build.swift` | what the build says about itself: version, number, the commit `package.sh` stamped and the update feed, parsed strictly, and `UpdatePlan`, whether this run checks for updates (pure) |
| `Updates.swift` | Sparkle, and the only file that imports it: the updater's lifetime, the feed pin, and the menu title while an update waits |
| `Settings.swift`, `App.swift` | the API key, the shortcut recorder, the update controls with the version line, the AI tools rows (the instruction editor and the copy buttons) and the privacy line in one window as tall as its rows or the screen's room, scrolling when the rows are taller; entry point, menu bar, reopen |
| `Palette.swift` | every color the app draws, and the glass material, as named tokens (see Color and glass) |
| `MCP/` | compiled into the app and into the helper: `AddCard`, the one parser of an `add_card` call, and `ToolReply`; `MCPServer`, the JSON-RPC side; `Endpoint`, `Socket` and `LineReader`, the socket each instance listens on; `HandOff`, the helper's connect, start and wait (pure apart from the socket calls); `Instruction`, the text an AI tool gets at a session start and its preference key, and `InstructionSource`, how the helper learns it without starting the app |
| `Helper/main.swift` | the `ideator-mcp` process: its arguments, starting the app that contains it, and the stdio loop |
| `AITools.swift` | the app's side: `ToolInbox` on this instance's endpoint (cards, and the helper's ask for the instruction), `HeldCards` while the welcome card waits, and the settings (`AIToolsChoice`) |
| `Connect.swift` | `AITool` and `HelperCommand`: the text each "Connect AI tools" button copies (pure) |

- **Location is ownership.** A `Card` value lives inside its location: a desktop entry (with its
  `Place`) or a stack position. There is no id-to-card map to keep in step,
  so "one card, one place" holds by construction, and a moving card carries its collapsed state
  and summary with it.
- **A place is a slot or a free point.** `Place` is `.slot(Slot)` or `.free(GridPoint)`, the
  center as a fraction of the screen, so a display change rescales free cards with no model
  change. Cards and the stack both have one. `Place.dropped(at:)` is the whole snap rule (snap
  within 15 % of a cell), and the drag guide asks it the same question while the pointer moves,
  so the guide can never promise a snap the drop won't make.
- **Overhang is a rendering rule.** `Grid.clamped` is the one place that says how far a free
  place may leave the screen (40 points of the header strip and of the width stay inside
  `reachable`, the screen minus menu bar and Dock; the top never rises). Computing a frame and
  reading a drag both go through it, and the model never does: a saved point keeps its raw
  fraction, so a smaller display pulls a card back while a larger one gives it back its spot.
  Snapped places are cells of `area`, so they always fit.
- **The stack is a loop with one blank page.** `Desk.stack` is the stacked cards, top first,
  and `Desk.selection` is the loop position: an index into the stack, or `stack.count` for the
  blank page after the bottom card. Next and previous move the position and never reorder the
  cards, so they undo each other and work with any number of cards. The order changes when a
  card enters or leaves and when the arranger moves one, and nowhere else. Every insert and
  remove goes through two helpers that keep the position on the same page, which is how "Pop",
  delete and an outside file removal all end up showing the next card; `arrange` is the third
  way a card changes place, and it keeps the position on the same card. Typing on the blank page
  appends a card at its position, so the new card stays selected and the blank page moves after
  it.
- **The stack arranger is a view of the stack, not a copy.** The order lives only in
  `Desk.stack`. `StackFace` carries the rows (a `CardID` and `Note.title`, top first), and the
  badge's count is derived from them. The arranger takes one derived value, `Arrangement` (the
  rows and the current card's id), and answers with two total commands keyed by `CardID`:
  `arrange(id, at:)` puts a card at an index and `showStacked(id)` turns the loop to it. Both
  ignore an id that is no longer stacked, so a stale row, a double drop or a card that left
  mid-drag changes nothing. While open, the list is patched by id on every render and never
  reloaded, so a drag in flight and the VoiceOver cursor survive; an equal `Arrangement` (most
  renders, such as a keystroke in the body) returns at once. The popover hangs from the stack
  view, not the badge, and `StackView.layout` hands it the badge's frame each time, so it
  follows the badge between the card's corner and the ribbon and closes when the badge goes.
- **One card view, two homes.** The stack shows its selected card with the same `CardView` a
  popped card uses. On the stack it does not drag and leaves its border to the stack. It shows
  the blank page when it has no card. The hover row's move button comes from one table,
  `CardView.Home.move`: "↩ Stack" on the desktop, "↗ Pop" on the stack, each with its tooltip
  and command. On a full desktop the stack greys Pop and sets its tooltip to "Desktop full".
  That flag is per desk, so `StackView` passes it to `CardView.apply` and it is not in `CardFace`.
- **Hide all is presentation.** `Visibility` lives outside the desk and is never saved. While
  hidden, New reveals just the card it brings out, and the stack window shrinks to its
  ribbon instead of ordering out. Pop goes with the stacked card, so it is unavailable then.
  The stack window gets the `Visibility` value itself: its ribbon-only shape, the count badge's
  place and the toggle button's icon all derive from it. The icon shows the current state (an
  eye while cards show, a slashed eye while hidden); the tooltip names what a click does.
  The toggle calls `DeskController.toggleHidden`, the path the global shortcut takes, not a `Command`.
- **The notes folder opens last.** `DeskController` creates `~/Documents/Ideator` when it is built, and
  that first access is what makes macOS ask for the Documents folder. `Launch.run` is the only caller
  of the closure that builds it, and it calls it after the welcome's Continue, or at once when no
  welcome is due. Whether it is due is a number in `UserDefaults`, the `WelcomeCopy.version` last
  acknowledged, read through `Preferences`: probing the folder to find out would be the access. The
  number is set after the notes open, so a launch killed inside the prompt shows the welcome again
  instead of a bare prompt. A scratch run (`-CardsFolder`) gets
  `Preferences(defaults: nil)`: factory values, nothing written, no welcome, and no global shortcut,
  and a `KeyStore` that never calls the Keychain, so a verify run can neither change nor take
  anything of the owner's.
- **One owner for the global shortcut.** `Shortcut` is legal by construction (⌘ or ⌃ plus one more
  modifier, so a hotkey never swallows ordinary typing). `HotKey` owns the chosen shortcut, its Carbon
  registration and why it is not registered. `choose` claims the new combination before it drops the
  old one, so a refusal leaves the working shortcut live. Carbon reports a conflict only inside one
  process, since two apps registering one combination both succeed, so Settings also says when macOS
  has its own shortcut on it (`CopySymbolicHotKeys`).
- **An AI tool's card enters like any other command.** The helper parses the call into `AddCard`
  and hands it over a Unix socket; the app parses the line again with the same `AddCard.parse`,
  since any process of the user can connect. `DeskController.add` reads one fact from the windows,
  whether the user is typing in the stacked card (Ideator active and the stack's editor first
  responder), sends `Command.addFromTool` with it, and replies once `saveNow` has tried to save the card, before any alert about a failed save.
  So where the card lands is a pure rule in `Desk.apply`, which the desk check explores. Before
  the notes open, `HeldCards` keeps the card and its reply until Continue, for 40 seconds at most
  from the AI tool's call.
- **Derived, idempotent side effects.** `render()` compares the desk with the real windows,
  `Library.save` with the disk, and `Summarizer.sync` with the requests in flight. Each is safe
  to run any number of times.
- **Editor.** TextKit 1. The text storage holds exactly the note's text. A body line's shape
  (its kind and level) is a paragraph attribute and its marker is drawn in the indent, so a
  marker can never be half-deleted. A run's bold and italic are a character attribute too, not
  the font. Fonts and indents are re-derived from the two attributes after every change; that
  pass writes neither, so undo restores shapes and styles exactly, even for text that sat in the
  header, whose font is always the header's, in between.
- **A level is part of the line.** A `Line` is a `LineShape` (kind plus a `Level`, 0 to 2) and its
  runs. `LineShape` drops the level of a plain line, so plain text always sits at the left edge.
  One pure function, `tidyLevels`, is the whole nesting rule: no item more than one level deeper
  than the list item above it, level 0 after a plain line, never past 2. `Note.init` applies it,
  so no `Note` holds a skipped level, whether it came from a file, the editor, a paste or a test.
  `listNumbers` counts per parent: a deeper run restarts at 1 and the parent's run resumes after
  it. Tab, Shift-Tab, Enter, Backspace and the list buttons are pure decisions in `Typing` over
  the body's shapes; a move takes the item and every deeper line after it as one block, and Tab
  is refused whole when the result would not already be tidy, so it can't drift from the rule.
- **One writer of shapes.** In the editor the paragraph attribute holds `"bullet"` at the top
  level, as before levels, and `"bullet:1"` deeper. `applyShapes` is its only writer and
  registers undo; every key decision ends there. After any edit the shapes are tidied the same
  way, in the edit's own undo group, so one undo of a deleted parent also brings back its
  child's level. While undoing or redoing, the tidy only checks afterwards without registering:
  the states undo brings back were tidy, and a change registered mid-undo would land on the redo
  stack. An edit that removes a line break starts its own undo step for the same reason.
- **The clipboard is a file boundary.** Copy and paste go through `Clipboard`, not the text
  view's own RTF. Copy writes the touched lines as the card file's Markdown (through `Note`'s
  writer) plus an HTML nested list; a selection inside one line is only its text. Paste reads an
  HTML list if one is there, with a hand-written tolerant reader. Otherwise each line of the
  text is first rewritten into the file grammar (`•◦▪·‣` bullets, `1)` numbers, `#` headings)
  and read by `Note`'s one reader, which keeps Markdown's backslash rule for files and pastes alike. `Clipboard.paste` splices the run
  into the note as a pure function; the editor then replaces only the paragraphs that changed, in
  one undo step.
- **Summaries.** A summary records the fingerprint of the note it describes, and is fresh while
  that matches. Within a run every summary comes from the current prompt, so only the sidecar's
  copy records which prompt wrote it (`SavedSummary.prompt`, a digest of the instructions), and
  `Desk.init` drops a saved summary from another prompt. Editing the instructions therefore
  regenerates every summary once. A sidecar from before the stamp holds summaries with no
  `prompt`, so it does not decode and is read as no sidecar (see 2026-10-27, old sidecars).
  Spinner, failure and "no key" are derived, not stored as flags.
- **One dependency.** Sparkle 2.10.0 is pinned exactly, `Package.resolved` is committed, and every
  `xcodebuild` passes `-disableAutomaticPackageResolution`, so a drifted pin fails the build instead
  of changing what ships. Only `Updates.swift` imports it. Xcode embeds and signs the framework
  without a copy phase of ours. `Cards/ThirdPartyNotices.txt` is Sparkle's license text and lands in
  Resources.
- **Whether a run checks for updates is a plan, decided once.** `BuildInfo.plan(isScratch:)` returns
  `.check(Feed)` or `.off(.notPackaged | .scratchRun)`. A build without `package.sh`'s stamp has
  build number 1, so every release would look newer and Sparkle would replace the copy Xcode built.
  Sparkle keeps its state in `UserDefaults.standard`, the owner's domain in a scratch run. The one
  exception is an update-test copy (`IdeatorUpdateTest` = YES, its own bundle id), which also may
  use plain http, and only to localhost or 127.0.0.1, and which may keep its scratch folder in its own
  preferences (see 2026-10-27, release scripts). `Updates` makes a
  `SPUStandardUpdaterController` only for `.check`, so an off plan has no Sparkle object at all,
  and starts it in `Launch.run`'s `openNotes`, after the welcome has announced the check. The
  Sparkle keys are literals in `Config/Info.plist`; `feedURLString(for:)` returns the plist's feed,
  so a `SUFeedURL` default or argument cannot move it. Settings binds its checkbox to Sparkle's
  `automaticallyChecksForUpdates` and keeps no copy.
- **Signing has one policy, checked in `package.sh` and carried out by `scripts/signing.sh`.** Builds
  are ad-hoc signed with the hardened runtime until a Team ID exists, and dyld then refuses the
  embedded framework ("different Team IDs"). The Release configuration therefore carries
  `Config/Ideator-adhoc.entitlements`, one key: `com.apple.security.cs.disable-library-validation`.
  `package.sh` checks the policy. With no Team ID the entitlements must be exactly that key. With one
  the key must be gone and every Mach-O under `Contents/Frameworks` must carry the app's Team ID.
  `sign_for_release` is what makes the second half true: for a Team ID build it signs the programs
  Sparkle ships inside its framework, then the framework, then the app, with the certificate the build
  was signed with, innermost first because signing any of them breaks the seal around it. For an
  ad-hoc build it does nothing. `verify-update.sh` seals its copies of the shipped app the same way
  (`seal_copy`: the shipped app's identity and entitlements, if it has any), so it proves the update
  in both worlds. `scripts/test-signing.sh` checks the order, identity and flags of every `codesign`
  call against a stand-in for `codesign`. `codesign --verify` passes an app that dies at launch, so
  `package.sh` also runs the packaged app as a scratch run and checks that it is alive with Sparkle
  mapped in. README, "When the Developer ID arrives", lists what to flip and delete.

## Color and glass

Cards sit beside windows that are mostly white: editors, terminals, Codex, Claude Code. A white
card with a sky-blue ribbon read as one more of them. The palette is warm paper instead: every
card is beige, and the stack's ribbon is the same hue one step darker, so the control center
reads as part of the card it sits on. All values are sRGB, live in `Palette` (`Palette.swift`), and nowhere
else; a view never writes a color literal. Cards always use the light look, in Dark Mode too, so
there is one set of values.

The paper is frosted glass. `configureAsCard(_:content:)` puts every card and the stack on an
`NSVisualEffectView` (`Palette.glassMaterial`, blurring what is behind the window), cut to
`CardShape` by a mask image. `CardShape.fillGlass` lays the translucent tint, the ribbon and a
white sheen at the top; `CardShape.strokeEdge` draws the outline and a white specular rim just
inside it. The glass stays `.active`, because Ideator is rarely the active app and inactive glass
turns flat gray. Of three prototypes (frosted paper, clear glass, beige glass), frosted paper was
chosen: it stays beige over white windows and only hints at what is behind.

| Token | Value | Used for |
| --- | --- | --- |
| `paper` | `#F4ECDE` at 78 % | the glass tint of the card body; at 85 % under the count badge in the ribbon |
| `ribbon` | `#E6D8BC` at 85 % | the stack's ribbon; at 55 % under the count badge on the card |
| `glassMaterial` | `.popover` | the blur behind every card |
| `sheen` | white, 10 % to 0 | the top half of a card, fading down |
| `rim` | white, 55 % / 5 % / 22 % | a 1.2 pt edge inside the outline, brightest top-left |
| `ink` | `#2B2520` | card text, the caret |
| `inkSoft` | `#716453` | list markers, summaries, card buttons, edge-band chevrons, Clarity when off |
| `inkFaint` | `#B3A68F` | the empty card's "Title" placeholder |
| `ribbonInk` | `#46361F` | New, the ribbon's icon buttons and the count badge |
| `line` | `#5A4630` at 18 % | card and stack outline |
| `shade` | `#5A4630` at 7 % | a hovered edge band |
| `guide` | `#5A4630` at 45 % | the dashed slot guide |
| `focus` | `#DDB880` | the 2 pt border of the card you are typing in |
| `accent` | `#823F1D` | a guide that will snap, Clarity when on |
| `danger` | `#9A2818` | "Desktop full" |
| `highlight` | `#E8D5AE` | selected text and the arranger's selected row; at 50 % the row of the card the stack shows |

`CardShape.radius` is 10 points.

Rules the values keep:

- One hue family. `paper`, `ribbon`, `focus` and the inks are hue 34 to 39°; only `accent`
  (20°) and `danger` (7°) step out, and only to mark a state.
- Contrast is measured on the rendered glass, since the tint is translucent. Over a white window
  the body renders `#F0ECE4` and the ribbon `#EAE2CF` (sampled from screenshots). On those:
  `ink` 12.8:1, `inkSoft` 4.9:1, `ribbonInk` 9.0:1, `accent` 6.1:1, `danger` 6.0:1. Body text and
  every ribbon label stay at 4.5:1 or more, bar one: Clarity when off is `inkSoft` on the ribbon
  at 4.46:1, so the quiet state reads as quiet next to New. Only the placeholder (2.0:1) is meant
  to be faint.
  Over a dark or saturated window the glass darkens a little, and the material's frost keeps the
  text readable; check a new token over both.
- The editing border is light on purpose (1.6:1 against the body). It marks the card you type in
  without the dark frame the old brown border made. It is `focus`, not the system accent color,
  which is blue for most people.
- Lines and shades are `#5A4630` at an alpha, not black, so they tint the paper warm instead of
  graying it.

To add a color, add a token with its use, check its contrast on the rendered glass, and add a row
here.

## Synthesis decision

Three candidate sketches were drafted in parallel (Opus, Fable, Sonnet) and scored by a separate
Fable judge. The Opus candidate is the base: it is the only one where every spec sentence has an
owner behaving as worded, and the judge agreed independently.

- Rejected from the Fable candidate: its edge switch rotates the stack (outgoing card to the
  bottom), which contradicts "the spot the incoming one left".
- Rejected from the Sonnet candidate: its single-array loop puts the outgoing card at the stack
  bottom on wrap-around, and its drag relies on `performDrag`, which does not block.
- Grafted from Fable: on an edge switch the existing window is re-pointed at the incoming card
  instead of closing and reopening, so there is no flicker and keyboard focus stays.
- Grafted from Sonnet: the list typing rules are pure functions (`Typing` in `Note.swift`), and
  only cards on the desktop request summaries, so a large stack does not fire a burst of requests.

Later changes, after trying the app:

- Edge bands moved from popped cards to the stack window, to show the cards hidden under the
  stack. Each popped card's stack cursor and the window re-pointing graft went with them; the
  stack itself is now the loop.
- The stack moved to the top-left cell and looks like one card: a sky-blue ribbon (the control
  center) above the selected card, with no list of the cards underneath.
- The stack's ribbon has a menu button with the menu bar icon's menu (one builder,
  `AppDelegate.makeAppMenu`), because a crowded menu bar can hide the icon behind the notch.
  Later it got its own Hide all button, so the ribbon's variant of the menu dropped the
  visibility items and Open Stack.
- Hover follows the pointer's real position (one mouse-move monitor in `DeskController`) instead
  of per-view enter/exit events, which a fast pointer can skip.
- 2026-10-22 revision: the selected stacked card became editable, with its own clarity, refresh
  and trash buttons. The loop gained the blank page, and a flip moves a position instead of
  rotating the stack, so the stack's order no longer changes when you browse it. Two-finger
  swipes switch cards; the edge bands stay as the click alternative. Clarity and summaries now
  cover stacked cards too, which reverses the Sonnet graft above. Hide all keeps the ribbon.
- 2026-10-22, free placement: cards and the stack can be dropped anywhere, with a guide outlining
  the slot a drop would snap to. The grid became 20 equal slots and the stack one more movable
  item. Sidecar version 2 adds free points and the stack's place.
- 2026-10-22, overhang and the ribbon toggle: free cards and the stack may hang off the left,
  right and bottom edges, never the top, as long as 40 points of the header strip and the width
  stay reachable. The stack's home moved to the top-right so Pop fills from the top-left.
  Hide all / Show all became a one-click button in the
  ribbon, and the count badge moved to the card area's bottom-right, into the ribbon only while
  Hide all has removed the card.
- 2026-10-22, beige: the blue ribbon and white card became the warm palette in Color, so cards
  stand apart from the white windows around them. The Hide all toggle's icon flipped to show the
  current state instead of the action.
- 2026-10-22, glass: cards and the stack became frosted glass with a beige tint, a sheen and a
  specular rim, and corners went from 9 to 10 points. The editing border went from dark brown to
  light caramel (`focus`), so it is less intrusive. The ribbon got lighter (`#D8C5A2` to
  `#E6D8BC`): a gentle step down from the body (1.1:1), not a separate band.
- 2026-10-22, Pop and Clarity: Pop left the ribbon and became "↗ Pop" in the stacked card's
  hover row, where a desktop card has "↩ Stack", so every card's buttons sit in one row. The
  ribbon is New and Clarity. Clarity lost its "On" and "Off" and shows its state by text color
  (`inkSoft` off, `accent` on), with the state in its tooltip and accessibility value.
- 2026-10-23, stack arranger: the count badge became a button that opens a popover listing the
  stacked cards, top first, to reorder by grip drag, ⌥↑ and ⌥↓ or VoiceOver actions, and to turn
  the stack to one. This is the one place besides entering and leaving that changes the stack's
  order.
- 2026-10-23, nested lists: list items gained a level (up to three), moved with Tab and
  Shift-Tab and saved as 4 spaces per level. Copy now writes Markdown and HTML lists, and paste
  reads them back, including lists copied from the Claude app or a terminal. Markers stay drawn,
  not typed; the clipboard puts them back as text.
- 2026-10-24, a newer sidecar: before strangers get beta builds, an older build must not destroy
  what a newer one saved, as when two Macs share the folder through iCloud. `Library` reads the
  sidecar's `version` on its own, since a newer file may not decode as a `SavedDesk`. Above this
  build's version, it places cards as best it can, never writes the sidecar, and still saves card
  files; `DeskController` says so once per launch. `Desk` is unchanged.
- 2026-10-27, three ways to lose a note, from the pre-release audit: quit ignored a failed save,
  `Library.load` treated a folder it could not list as empty (so the next save wrote a sidecar
  that knew none of the places), and the newer-sidecar check ran only at launch. Now
  `applicationShouldTerminate` asks "Quit without saving?" while the folder refuses; a folder that
  can't be listed locks the sidecar for the run the way a newer one does, with its own notice; and
  `save` reads the sidecar's version again before every write. `DeskController` takes a `present`
  closure for its alerts so tests can answer them. `Desk` is unchanged.
- 2026-10-27, paragraph separators: the audit reproduced a trap in copy and paste after an
  HTML paste carrying U+2029. `Note(attributedText:)` splits paragraphs on "\n" alone, while
  `allParagraphs()` uses `paragraphRange`, which also splits on CR and U+2029, so the storage had
  one paragraph more than the note and `span(of:)` indexed past the end. The invariant now holds
  at the storage boundary: `attributedParagraphs` shows every other line break as a space, whatever
  put it in a run (an HTML paste, a file edited elsewhere), and `HTMLReader.add` collapses
  Unicode's line breaks like HTML whitespace. The two splitters stay as they are.
- 2026-10-27, hover buttons, the 2026-10-21 finding the audit found still open: the buttons were
  hidden by alpha alone, which AppKit ignores when it hit tests, and hover changed only on a mouse
  move, so after Show all a click with no move first acted on a button nobody could see. The row
  (`HoverButtons`) now refuses the hit test while hidden and the press goes to the card under it.
  It stays in the accessibility tree, not `isHidden`, because VoiceOver users cannot hover and the
  verify recipes press the buttons by name. `DeskController` checks hover after every render, and
  each window answers by the frame `apply` gave it, since a move slides there and `frame` lags.
  The title's room comes from the row: the collapsed title ends before it, and the editor wraps
  the title around it with an exclusion path, so only the lines beside the row are short. The
  76 pt reserve it replaces had fallen behind a row of 91.5 pt (111.5 pt collapsed, with Refresh).
- 2026-10-27, files written elsewhere: the reader dropped a backslash before any character and
  took any pair of asterisks for emphasis, so `C:\Users\me` showed as `C:Usersme` and
  `rm *.txt *.log` lost its stars, and the first edit wrote that back. `parseInline` now follows
  CommonMark: a backslash escapes only ASCII punctuation, and a run of asterisks closes only after a
  non-space and opens only before one. The writer is unchanged: it escapes every `\` and `*`, which
  the new reader reads back, so a card Ideator wrote keeps its bytes, its digest and its cached
  summary. The one non-CommonMark rule left is the writer's own `\1.` before a plain line that
  starts like a numbered item. Paste lost `keepingLiteralBackslashes` with it, since `Note`'s
  reader now applies that rule itself. That reader also decides `*` in a paste of several lines,
  so `2 * 3 * 4` and `** spaced bold **` paste as typed where the old one styled them and dropped
  their stars, and `*a *b*` pastes as italic `a *b`.
- 2026-10-27, undo and inline styles: bold and italic lived only in the fonts, read back by point
  size, and `restyle()` re-derives every font after each change without registering undo. Text
  joined into the header took the header's font, so undo brought its characters back plain and
  the next save dropped the `**` and `*`. Bold and italic are now the `.cardStyle` attribute of
  each character, written only by `attributedText`, ⌘B/⌘I and typing; fonts follow from it and
  are never read back, and undo restores it with the text, as it does `.cardLine`. Reading the
  font's traits at any size would not have done it: the header font is bold, so every line that
  passed through the header would come back bold. Text in the header keeps a style it does not
  show, so Enter that splits it back out of the header also brings its style back.
- 2026-10-27, Tab on a selection: `Typing.onTab` took "touches one line" for "is a caret", so a
  selection inside a list's first item, or from the header into it, became a tab character, and
  the second case merged the item into the header. The editor now says whether it holds a caret,
  and a selection that touches an item gets the move or nothing, as the spec's "Tab does nothing"
  and the spec gap below already said. A selection over plain lines only still becomes a tab.
- 2026-10-24, first launch: a stranger opening the dmg met macOS's Documents prompt with no
  explanation and a shortcut that fought Finder. `Launch.run` now builds the `DeskController`,
  whose `Library.load` creates the notes folder, only after a welcome card's Continue, and records
  the card as seen once the folder opened. The global shortcut became ⌃⌥Space (⌥⌘C is Finder's Copy
  as Pathname), chosen in Settings through `Shortcut` and `HotKey` and kept by `Preferences`. A
  scratch run reads and writes no preferences and registers no shortcut, so a verify run can't
  touch the owner's. Settings says what summaries send, PRIVACY.md says it in full, and the app
  got a placeholder icon. `Desk` is unchanged.
- 2026-10-24, the default moved to ⌃⌥I: with several input sources macOS enables "Select next
  source in Input menu" on ⌃⌥Space and takes the key before Ideator sees it, so the cards did not
  move. ⌃⌥I is on none of macOS's symbolic hotkeys. `SettingsWindow` also refreshes whenever it
  becomes key, since the cached window kept showing the macOS-shortcut advisory and key status
  from its first opening.
- 2026-10-25, build stamp: the build number is a commit count, so a branch build and `main` after
  its squash merge share one, and the laptop's copy could not be told from the release. `package.sh`
  now passes the commit and whether the tree has changes (untracked files included) as the build
  settings `IDEATOR_COMMIT` and `IDEATOR_TREE_DIRTY`. `Config/Info.plist`, outside the synchronized
  `Cards/` group, turns them into `IdeatorCommit` and `IdeatorTreeDirty`, so they are inside the
  signature: a plist edited after signing would not verify. The project defaults are `none` and
  `unknown`, which is what an Xcode build carries. `BuildInfo` parses the two keys at the boundary and
  has a stamp only for a 40-digit lowercase hex commit with a tree state of YES or NO, so a half-valid
  stamp reads as a development build and "unknown" is never clean. Settings shows the version line,
  and `scripts/installed-build.sh` compares an installed app with `origin/main` by commit, then by
  tree, then by ancestry. `Desk` is unchanged.
- 2026-10-26, Sparkle embedded: updates start with the framework in the app and nothing using it. A
  Release build with the hardened runtime and an ad-hoc signature could not load it, so Release
  gained the one entitlement above, `package.sh` gained the signing policy and a launch check, and
  Xcode's own embed was kept after checking that it copies and signs the framework. `Desk` is
  unchanged.
- 2026-10-26, scratch runs and the Keychain: a scratch run already had detached preferences, but
  `KeyStore` still read the login Keychain at launch, so on a Mac with a saved key every new ad-hoc
  build raised macOS's access prompt and froze the unattended verify runs and the `package.sh`
  launch check. `Launch.keys()` now gives a scratch run a `KeyStore` that keeps the key in memory
  and makes no Keychain call. `Desk` is unchanged.
- 2026-10-26, updates: Sparkle checks GitHub Releases once a day, announced by a fifth welcome
  paragraph and started only after Continue. The menu bar icon's menu gained Check for Updates…
  and Settings an Updates section; the ribbon's menu is unchanged. The privacy line moved to the
  end of Settings and, with PRIVACY.md and the welcome card, now names GitHub as well as Anthropic
  and what GitHub sees. `package.sh` refuses a release whose feed or key is not the production one,
  or that turns on profiling, automatic installs, the update-test flag or an ATS exception. `Desk`
  is unchanged.
- 2026-10-26, update proof: `scripts/verify-update.sh` updates an installed build N to N+1 through
  Sparkle against a local feed, with a forged feed and a forged disk image as negative cases. It
  copies the shipped app twice with a test bundle id, feed, throwaway key and `IdeatorUpdateTest`,
  seals each with the original entitlements and checks their code equals the shipped code, so the
  path it proves is the shipped one. The feed names `localhost` and its server answers on both
  `::1` and `127.0.0.1`, so the app connects over `::1`: a connect to 127.0.0.1 once went
  unanswered for eight seconds on this Mac, with `::1` fine. `Desk` is unchanged.
- 2026-10-26, releasing: `scripts/release.sh` turns the tip of `origin/main` into a draft GitHub
  release holding the disk image and a signed one-item feed, and a second command, `--publish`,
  makes it live, because publishing is the step nobody can take back and the draft is where a
  person reads it. It takes the repository and the download address from `SUFeedURL`, the one place
  the project names them, and refuses unless the Keychain's key is the one the app trusts. It parses
  the feed it made instead of trusting it, and compares the draft's files with the local ones before
  the draft goes live. Every step looks at what exists first, so a run that stopped carries on.
  Notarization is not in it yet. `Desk` is unchanged.
- 2026-10-27, replacing the API key: a summary job kept the key it was created under for as long as
  its note was unchanged, so a request waiting out its quiet period or already in flight went out
  with the key the user had just replaced, and its 401 landed after `forgetFailedSummaries` had
  swept, leaving the card on "Summary unavailable" under a good key. A job is now for one version of
  one note under one key: `Summarizer.sync` cancels a job whose key is no longer the saved one and
  starts it again at once, as for any card that has no job. A removed key already cancelled every
  job. `Summarizer` takes the request itself as a closure, `Anthropic.summarize` by default, so
  `SummarizerTests` can hold a request, check its key and answer it by hand. `Desk` is unchanged.
- 2026-10-27, release scripts: the Developer ID switch is "flip the two build settings, delete the
  entitlement, run `package.sh`", and `verify-update.sh` passes before and after it. `package.sh`
  signs Sparkle's helpers for a Team ID build, and the update proof seals its copies with whatever
  identity and entitlements the shipped app has, where it had assumed ad hoc plus the bypass. A scratch
  run is now the `-CardsFolder` launch argument and nothing else: `Launch` read every defaults domain,
  so a stray `defaults write` turned the owner's Ideator into one (no Keychain key, no shortcut, no
  welcome, no update checks, notes elsewhere). The exception is an update-test copy, which also reads
  its own `CardsFolder` default, because Sparkle relaunches an app with no arguments and the
  relaunched copy would otherwise be a normal run that reads the owner's Keychain and registers the
  shortcut. `verify-update.sh` passes the argument for every launch it makes and writes the default
  only before the relaunch, so the argument path stays proven. Its feed server now listens on `::1`
  and `127.0.0.1` rather than on every interface. `Desk` is unchanged.
- 2026-10-27, a welcome that can change what it discloses: `WelcomeSeen` was a Boolean, so a Mac that
  acknowledged the card before the GitHub paragraph arrived never saw it, and Sparkle's first request
  went to GitHub unannounced, against "never before Continue". The key now holds `WelcomeCopy.version`,
  the card last acknowledged, and the card shows while that is below the current version. A stored
  `true` reads as 1 (`integer(forKey:)`), so nothing migrates, `defaults delete com.systemlabs.Ideator
  WelcomeSeen` still resets it, and an older build run after a newer one stays quiet. When the
  Anthropic or GitHub paragraphs change what they say Ideator sends or asks, raise the version: a test
  pins both paragraphs beside the number and its failure says so. Version 2 is the first versioned
  card. `Desk` is unchanged.
- 2026-10-27, what the privacy text says: PRIVACY.md said a summary "is not requested again until the
  text changes". The rule is that a card is sent whenever it has no summary for its text as it is
  now, so a failure (never saved), an outside edit, a build whose prompt changed and a launch that
  could not save summaries all send it again. PRIVACY.md lists those triggers, and Settings and the
  welcome card state the rule in the same words, which a test pins. Remove Key discarded
  `KeyStore.set`'s result, so a refused Keychain delete told the controller the key was gone while the
  key kept sending. It now beeps like Save and tells nobody. `KeyStore` lost `final` only so a test can
  subclass it and refuse. `Desk` is unchanged.
- 2026-10-27, old sidecars: version 2 has been the sidecar format since 2026-10-22, before the first
  disk image, and a build before beta owes no file compatibility, so the code that shifted a
  version-1 file's slots served nobody. It also held the one trap in `Desk.init`: a version-1
  sidecar whose slot is `Int.max` overflowed the shift at every launch. `Desk.init` now reads a
  sidecar older than this build's version as none: every card in the stack, the stack at its home.
  `SavedSummary.prompt` stopped being optional for the same reason, so a sidecar from before the
  prompt stamp (2026-10-24) fails to decode and is read as none too.
- 2026-10-28, summaries with an Anthropic or an OpenAI key: users without an Anthropic account should
  still get summaries on day one of the public build, and OpenAI keys are the common ones. Settings
  keeps one key field. `Provider` is chosen from the key's start (`sk-ant-` is Anthropic, anything
  else OpenAI) in one initializer, and `Anthropic` and `OpenAI` are only wire formats, each a request
  builder and a reply reader; `Provider.summarize` is the one transport and the one place an error
  becomes a reason. OpenAI goes through the Responses API with `gpt-6-luna` (no SDK, `store: false`,
  low reasoning effort, no `temperature` or `top_p`) and its text is read from the `output_text` parts
  of `message` items by type, because the output begins with a `reasoning` item. The prompt is shared:
  `scripts/check-summaries.sh` runs the real request over sample cards against the spec's rules, so
  a rule a model breaks is fixed in `Summary.instructions` for both companies. The Keychain item is
  now the neutral account `api-key`, the old `anthropic-api-key` one is not migrated (before beta),
  and the privacy line, the welcome card (version 3) and PRIVACY.md name the company that gets the
  text. A key from any other service goes to OpenAI and fails with HTTP 401 on hover, in exchange for
  no base-URL field. `Desk` is unchanged except the reason for a card with no key, which no longer
  says Anthropic.
- 2026-10-28, the prompt's language rule: the first `check-summaries.sh` run with `gpt-6-luna` gave
  three English cards a Chinese summary, each opening with one of the prompt's Chinese kind labels,
  and ran a Chinese card full of English terms to 82 characters. The language rule now comes second
  in `Summary.instructions`, names English as well as Chinese, says the examples never set the
  language, and ties the Chinese kinds to notes in Chinese; the CJK budget counts every letter,
  digit, space and mark. The same text goes to both companies, so the rerun with each key is the
  proof. `Desk` changes only in that text.
  The second run kept every summary in its card's language but ran three past the length limit
  (133 and 138 characters for English, 75 for Chinese), each listing every point of its note. The
  limit is now a hard ceiling with a lower aim (15 to 18 words, 40 to 50 CJK characters), the gist
  comes only if it fits, the model picks one or two main points (a to-do list still names every open
  item), and a thin card gets at most half the limit; nothing measures or cuts the reply.
  The third run, with both companies, had 5 hard fails in 304 checks: Haiku answered the Chinese thin
  card in English, opening with the prompt's English fallback "Notes on"; both ran the Chinese card
  full of English terms to 77 and 82 characters by copying every term; and `gpt-6-luna` listed the
  whole numbered launch plan as a "to-do list" (134 characters). Each kind list now carries its own
  fallback ("Notes on" for English, "笔记：" for Chinese), a CJK note names at most two English
  terms and drops key prefixes, versions, IDs and links, and only `[ ]`/`[x]` lines make a to-do
  list, so any other list gets its one or two main points.
  The fourth run (prompt `e37df450`) had 1 hard fail in 304 checks: Haiku wrote the English thoughts
  card as two sentences, the second a "Next step", 138 characters. The Chinese card full of English
  terms passed on both (51 and 53), so the CJK count stays as the spec has it. The prompt now asks
  for a single sentence, gives the ceiling in words too (about 18, aim 12 to 16), puts a thin card at
  about 8 words or 30 CJK characters with no padding, and has an all-done list name none of its items.
  The fifth run (`1f718b33`) cleared `gpt-6-luna` and left 1 hard fail on Haiku: its meeting notes
  ran to 138 characters, and every long Haiku summary gave all three points of its note whatever the
  word count said. So the gist is now at most two points, never a third, and the prompt shows the
  short form by example (meeting notes with two points, an all-done list, a thin question), none on a
  sample card's topic.
  The sixth run (`b15b8f30`) passed: 28 of 28 requests, 0 hard fails in 304 checks, longest English
  summary 126 characters and the mixed Chinese card 55 and 57. One warning, Haiku's thin Dentist card
  at 62 characters against 60 expected, is left as a judgment call.
- 2026-10-28, AI tools add cards (MCP, step 2 of CARDS-SPEC.md's AI tools section). The server is a
  Swift command-line target, `ideator-mcp`, embedded at `Contents/Helpers` and signed with the app,
  so notarization and Sparkle cover it and the user installs nothing: an npm or Python server would
  need a runtime on the Mac and a second way to update. The helper never writes a card. It hands
  the card to the running app, which saves it, so the notes folder keeps one writer (`Library`'s
  snapshot assumes it), the AI tool's process never meets macOS's Documents prompt, and the app
  knows the card came from an AI tool. `Desk` gained `Command.addFromTool`, with its rule in the desk
  check and seven mutants.
  - Transport: a Unix domain socket in the user's own temporary folder (`confstr`, so the tool's
    environment cannot move it), mode 0600, one line of JSON each way, the framing MCP's stdio
    binding itself suggests for sockets. "Is Ideator running?" is whether the socket answers, never a
    process or bundle-id lookup, since the owner's Ideator shares the bundle id. A normal run listens
    on `ideator-mcp.sock` and a scratch run on `ideator-mcp-<16 hex digits of its folder>.sock`, so a
    helper reaches only the run its `-CardsFolder` names. The digits hash the folder's `realpath` (the
    part that exists), since the app opens the folder by the path it is given and the file system
    follows links and ignores case: `/tmp/x` and `/private/tmp/x` are one run. A file left by a killed
    run is replaced when nothing answers on it, and `close` removes only the file this instance made.
    SIGTERM removes it too, from a signal source off the main thread, then ends the process as the
    signal would. Rejected: an XPC Mach
    service, which needs a launchd job (`SMAppService`), one name per bundle, and none for a scratch
    run; `CFMessagePort`, whose reply must come back inside the callback on the main thread, so it
    cannot wait for Continue; loopback TCP, open to every local user and needing a port to be found;
    Apple Events, which find the app by pid or bundle id and ask for Automation permission; and an
    inbox file in the notes folder, which makes the tool a writer and brings back the Documents prompt.
  - With nothing answering, the helper starts the app that contains it by its URL, never by bundle
    id, with `activates` off and `IDEATOR_BACKGROUND=1`, so `openNotes` skips its `NSApp.activate()`.
    A scratch run asks for a new instance: Launch Services would otherwise give the request, and
    not its arguments, to the owner's running Ideator.
  - The helper serves both MCP eras: `initialize` for 2025-11-25 and earlier, and the stateless
    2026-07-28 protocol (`server/discover`, the version and capabilities in each request's `_meta`,
    `resultType` on each result). A session start never reaches the app, so an AI tool opening a
    session does not start Ideator.
  - While the welcome card waits for Continue the app listens already, and holds a card 40 seconds
    at most, then answers "press Continue" and drops it. Codex and the MCP TypeScript SDK give up on
    a call after 60 seconds, and a card saved after the tool gave up would be added again when the
    tool retries. The app keeps the deadline, not the helper, so the answer and the save cannot
    disagree; a Documents prompt that holds the main thread past it still refuses. The helper sends
    how much of the 40 seconds the launch left (`waitMs`), so the bound holds from the call, and the
    app holds each card on a strict dispatch timer with 10 ms of leeway. Before, a `Task.sleep` of
    40 s started when the card reached the app, after the launch, with the system's default leeway,
    and a verifier measured the answer 42.8 s after the call. The helper's own wait for an answer
    ends 50 s after the call, longer than the welcome wait, and says the card may still be saved.
  - A first failed save alerts after the reply, from a `CFRunLoopPerformBlock` block on the main run
    loop, not the main queue: the alert is modal, and an AI tool that waits for it gives up and adds
    the card again. A modal loop started from a main-queue block held every later main-queue item,
    so a second card waited for OK.
  - MCP 2026-07-28 caching hints: `server/discover` and `tools/list` say `ttlMs: 0`, since the
    instructions are the user's to edit and an update changes the tool, and a local helper is cheap
    to ask again; `cacheScope` is `private` for the instructions and `public` for the tool list.
  - `package.sh` checks the helper's signature, runtime, team and slices, and its launch check hands
    the scratch run a card through the shipped helper and reads the saved file. The check opens a
    real window, so it takes the live-UI lock, waiting up to 30 minutes for it.
- 2026-10-28, the instruction and the Connect section (MCP, step 3). `Instruction` is the edited text
  or nothing (`edited: String?`), so no `AIToolsInstruction` key in the preferences means the standard
  text, and a later build's standard text reaches everyone who never edited it. Typing the standard
  text back is no edit. A blank text is kept as blank and sends no `instructions` field, because
  someone who clears the editor wants none; Reset to Default is the way back.
  - How the edit reaches the helper without starting the app (step 2's rule that a session start never
    starts Ideator): the helper asks a running instance first, with one line, `{"request":"instruction"}`,
    on the socket cards use, and the app answers from memory. With no answer inside 2 seconds it reads
    the app's saved preference (`CFPreferencesCopyAppValue` on the bundle id of the app that contains
    it, so an update-test copy reads its own), and a scratch helper falls back to the standard text.
    Both halves are one `InstructionSource` in `MCP/`, and the app stays the only writer of the notes
    folder and of its preferences. A scratch run saves nothing, so its edit exists only in the process:
    the socket carries it while the run is up, and when the run quits it is gone, as "lasts for the
    run" says. A normal run saves each keystroke to its preferences, so the helper finds the edit with
    Ideator closed. An app from before this change reads the ask as a card with no title and answers
    with an error, which the helper treats as no answer.
  - Rejected: a file the app writes for the helper. In the temporary folder, macOS cleans the file out,
    and a killed scratch run would leave an edit for the next helper to read. In Application Support
    it is a second copy of a setting and a new place to document, and the scratch case still needs
    another carrier. In the notes folder it makes the AI tool's process read `~/Documents`, which is
    the Documents prompt step 2 exists to avoid. Preferences alone could not carry a scratch edit,
    so verify-cards could never see one. The socket alone would show the standard text whenever
    Ideator is closed, which is when most sessions start. Starting the app to ask breaks step 2.
  - A normal helper asks the socket too, rather than going straight to preferences, so the path the
    live proof exercises is the path the owner's helper takes while Ideator is open. The preference
    read is covered by unit tests, since a live proof of it would write the owner's domain. An app
    whose main thread is busy (the Documents prompt) answers late, so the ask is bounded and the
    saved text, which is the same value, is the answer then.
  - Connect: `AITool` names the three tools and `setup(for:)` writes each one's text from a
    `HelperCommand`, the helper's path inside `Bundle.main` and, for a scratch run, `-CardsFolder
    <folder>`. Claude Code gets `claude mcp add --transport stdio --scope user ideator -- <helper>`;
    the default scope is the current project only, and a note app belongs to every project. Codex gets
    a `[mcp_servers.ideator]` table, Claude Desktop the `mcpServers` object. Shell words are single
    quoted when they need it, and TOML and JSON strings come from `JSONSerialization`, so a path with
    a space, a quote or a backslash survives. A unit test hands the shell words to zsh and reads them
    back. Rejected: `codex mcp add` for Codex, since the spec asks for a config line and the table
    is what a user can see and edit afterwards; a launch-time check that the helper exists, since
    a copy from a build without one fails visibly in the tool.
  - The copy buttons write to `NSPasteboard.general` only on a click, and the unit tests write to a
    pasteboard of their own, so a test run never replaces the clipboard.
  - The two blocks made Settings' rows 950 points tall (a 982-point window with its title bar), more
    than a 13-inch display has below the menu bar,
    and the window is not resizable. Its rows now sit in a scroll view over a flipped document view, and
    the window is as tall as the rows or as the screen's visible room (minus the title bar and 24
    points), whichever is less, so a short screen scrolls from the Shortcut row and a tall one shows
    everything. Rejected: shrinking the rows to fit (the instruction box and three buttons need about
    300 points), and collapsing the two blocks behind disclosure arrows, which hide the Connect
    buttons from the user who comes for them. A unit test sets the room through `maxContentHeight`;
    capped scrolling on a short screen was not driven live, since this Mac's display fits the window.
  - A limit on the instruction. The reply to the helper's ask is a JSON line that `InstructionSource`
    reads up to 1 MiB, and a verifier found that a text of 200,000 control characters (1.2 MB as JSON)
    came back past that, was dropped as too long, and left the helper serving the standard text with no
    sign of it. The text now holds up to 100,000 bytes, which JSON writes in at most about 600,000
    (every control character becomes six bytes), so every text the editor takes reaches the helper.
    `Instruction` holds the limit itself: `edit(to:)` and the read of the preferences both cut a longer
    text between characters, so a text written with `defaults write` is bounded too. The Settings box
    refuses a change that would pass it and says so in the line above, since a keystroke that does
    nothing needs a reason. Rejected: raising the helper's read limit for this reply, which moves the
    failure to a larger text and leaves the editor with no size it can promise, for a text about 200 times the
    standard one, which an instruction has no use for.
  - Connect from a place that goes away. A copy button writes the helper's path inside `Bundle.main`.
    From a disk image, or from the copy Gatekeeper runs a downloaded app from until it is moved
    (`.../AppTranslocation/<uuid>/d/Ideator.app`), that path is gone after the eject or the next
    launch, and the pasted setup fails in the AI tool at a later session, far from where it was
    copied. `RunPlace.isTemporary` is the rule, and the file system answers it: the app is not on the
    startup volume (`volumeIsRootFileSystem` is false), or its path has an `AppTranslocation`
    component, the only sign of a translocated copy that needs no private API. A path the file system
    cannot find has no answer and does not count. A first version decided by the path string, with
    links followed: it passed here and failed on CI, whose runner has a link to the startup volume in
    `/Volumes` but no app at the path, so there was nothing to follow. Then the buttons are dimmed and
    the line above them says to move Ideator to Applications. Rejected: copying anyway with a warning,
    since the user pastes before reading it; asking DiskArbitration which volumes are disk images, when
    one flag already separates them from the startup volume; and exempting other volumes, which can be
    unplugged as an image can be ejected (the cost: someone who keeps the app on an external drive moves
    it to use Connect). The disk image case was driven live with a scratch image (recipe
    `mcp-connect-volume`, also at a mount point outside `/Volumes`); the translocated case was not, since
    only Gatekeeper makes that copy. The unit tests hand `RunPlace` the file system's answer and a path
    for both cases, and read the host's own answer for every volume it has mounted.
  - `MCPServer` is `nonisolated` like the rest of `MCP/`: the helper's server asks the socket from
    its own thread, and a test must be able to do the same without the main actor.

## Tradeoffs accepted

- We accept re-rendering every window after every command in exchange for one funnel with no
  "what changed" bookkeeping. Each setter compares before touching AppKit.
- We accept timestamp file names (`2026-10-21 153012.md`) in exchange for an identity that never
  changes.
- We accept rescanning the folder when the app becomes active, instead of live file watching.
- We accept that pressing on the header and moving drags the card instead of selecting text;
  double-click and shift-click still select.
- We accept a burst of summary requests at launch when many stacked cards have none cached, in
  exchange for every card having a summary under the same rules.
- We accept the Keychain for the API key, which may ask for access again after each rebuild of an
  unsigned debug build. A scratch run gets `KeyStore(inKeychain: false)`, as it gets
  `Preferences(defaults: nil)`: the key lives in memory for that run, nothing reaches the Keychain,
  so no prompt can block a verify run or the `package.sh` launch check.
- We accept that ad-hoc Release builds do not validate the libraries they load, in exchange for
  embedding Sparkle before the Developer ID exists. The hardened runtime stays on, so debuggers and
  `DYLD_INSERT_LIBRARIES` still cannot reach the process. `package.sh` fails a build that has a Team
  ID and still carries the entitlement, so the exception cannot outlive its reason.
- We accept that an empty last list item keeps its shape only in the typing attributes, as an
  empty last line's kind always did: it has no character to hold the attribute. It is lost on
  reload, and after typing in it then undoing, it shows the shape of the line above until the
  next undo.
- We accept that a nested card is rewritten with 4-space indents only when it is next saved for
  another reason, since saving compares notes, not file text.
- We accept owning an HTML reader (about 200 lines) in exchange for one that is pure, tested on
  fixtures shaped like Notes, Google Docs, the Claude app and web pages, keeps checkboxes and never
  touches WebKit during a paste.

## Alternatives considered

- **Normalized store** (`[CardID: Card]` plus slot, stack, collapsed and summary maps): every
  transition must keep several keyed structures in agreement.
- **Literal marker characters** in the text: native-feeling copy/paste, but the user can edit a
  marker out of sync and every edit needs a renumbering pass that shifts the selection. Copy and
  paste get the markers from `Clipboard` instead.
- **Turning the hardened runtime off for ad-hoc builds** instead of adding the entitlement: also
  lets the framework load, but it lets debuggers and injected libraries read the API key out of
  the app's memory, which the hardened-runtime check exists to prevent.
- **Nesting as a tree** (`Line` with children): moving a block would be one splice, but every
  editor paragraph would need a path, and the text view is flat. A level per line plus
  `tidyLevels` keeps the flat model.

## Spec gaps resolved

- New on a full desktop beeps, shows "Desktop full", and shows the stack's blank page with the
  cursor in it. While hidden, that also brings back the stack's card area.
- "↩ Stack" shows the returned card on the stack, so you see where it went.
- Switching the stack to another card takes the cursor out of the editor, so typing never lands
  in a card you did not click.
- A file added outside the app while Clarity is ON joins the stack collapsed.
- While hidden, swipes and edge bands do nothing: there is no card area to switch.
- The menu bar menu adds "Settings…" so the API key has somewhere to go.
- With no API key, a collapsed card shows "Summary unavailable" with the reason on hover ("No API key.
  Add one in Settings.").
- A collapsed card whose body is empty or one line shows that line in the lighter style.
- The grid uses the menu-bar screen and does not subtract the Dock. Only the overhang limit
  does, so a header can't hide under it.
- The count badge sits at the bottom-right of the stack's card area: the hover buttons are at
  the top-right and the formatting bar's buttons at the left, so it covers neither. It is the
  arranger's button, so a press on it opens the arranger instead of placing the caret in the
  text under it; with no stacked cards it is disabled and takes no click, so a press falls
  through as before. Under Hide all, in a ribbon too narrow for it beside the toolbar and the
  buttons, it is hidden, and "Desktop full" truncates first, so no button ever moves.
- Showing a card from the arranger while Hide all is on brings back the stack's card area and
  nothing else, the same precedent as New on a full desktop, because "show that card" means
  nothing without a card area. Moving cards reveals nothing. The rule is `Visibility.reveal(after:)`,
  next to the New and Pop rules it joined.
- A drag whose card leaves the stack is refused at the drop rather than cancelled: AppKit has no
  API to cancel a session from outside, so the row slides back on release, and the desk would
  ignore the gone id anyway.
- Free cards piled into one slot leave other slots untaken, so Pop also stops at 19 cards on the
  desktop, keeping the old ceiling.
- The guide window sits above the dragged card and ignores the mouse; a swap target shows the
  same outline as an empty slot.
- Tab where no item can nest (the header, a plain line, a list's first item) types a tab
  character, as before nesting existed. Paste and Match Style is not offered.
- Shift-Tab on the header or a plain line does nothing, so the keyboard never leaves the card.
  Tab on a selection that holds an item which can't move (a list's first item) moves nothing,
  and never replaces the selection with a tab.
- A multi-line paste inside text puts the text after the caret at the end of the last pasted
  line, as pasting in any text editor does.
- Pasted text and a card file keep a backslash that Markdown keeps (`C:\Users`, `a\nb`); only a
  backslash before punctuation escapes it, besides the writer's own `\1.` for a plain line that
  starts "1. ".
- An update shows the welcome once to someone who already uses Ideator when the card's version rose
  (the shortcut changed in one update, the GitHub paragraph arrived in another), in exchange for one
  first-launch rule, a recorded number below the current one, and no migration code.
- A conflict with another app's global shortcut can't be detected, since two apps registering one
  combination both succeed. `HotKey.problem` covers what Carbon refuses inside this process, and
  Settings warns about macOS's own shortcuts, which are the one other conflict that can be read.
- The welcome is taller than a grid cell, in exchange for its copy fitting at body size in the
  stack's width. It is top-right where the stack appears.
- A card from an AI tool with Top keeps the page while the cursor is in the stack's editor, the
  blank page included, since a first character there is about to become a card.
- An edit of the instruction reaches an AI tool at its next session, never the one running, because
  MCP gives server instructions once, at `initialize`. A tool that caches them longer is that
  tool's choice.
- A card from an AI tool that cannot be saved stays in the stack, as any unsaved edit does, and the
  reply says not to add it again, because a retry would add a second copy.
- The welcome card that a background start shows comes to the front with `orderFrontRegardless`,
  neither key nor active, so a Return typed in the AI tool stays in the AI tool. A click on the card
  brings Ideator forward and makes Continue work. macOS 15 already refused the card's
  `NSApp.activate()` from a background start in a test, but that refusal is macOS's policy to change,
  so the card no longer asks.
