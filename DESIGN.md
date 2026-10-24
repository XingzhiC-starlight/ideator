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
| `Summarizer.swift` | summary requests and the one Anthropic call |
| `CardWindow.swift`, `CardEditor.swift` | the card window, press routing, and the text view |
| `StackWindow.swift`, `Swipe.swift` | the stack window and its count badge; the rules that turn scroll events into flips (pure) |
| `StackArranger.swift` | the popover off the badge that reorders the stack, and the `Arrangement` value it reads (see The stack arranger) |
| `HotKey.swift` | `Shortcut`, the legal global key combination, and `HotKey`, its one registration with Carbon: chosen shortcut, registered or not, and why not |
| `Launch.swift`, `Preferences.swift` | how the process was started (`-CardsFolder` makes a scratch run); the persisted shortcut, and no persistence at all in a scratch run |
| `Settings.swift`, `App.swift` | API key and settings; entry point, menu bar, reopen |
| `Palette.swift` | every color the app draws, and the glass material, as named tokens (see Color and glass) |

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
- **Derived, idempotent side effects.** `render()` compares the desk with the real windows,
  `Library.save` with the disk, and `Summarizer.sync` with the requests in flight. Each is safe
  to run any number of times.
- **Editor.** TextKit 1. The text storage holds exactly the note's text. A body line's shape
  (its kind and level) is a paragraph attribute and its marker is drawn in the indent, so a
  marker can never be half-deleted. Fonts and indents are re-derived from the content after
  every change; that pass never writes the shape attribute, so undo restores shapes exactly.
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
  text is first rewritten into the file grammar (`•◦▪·‣` bullets, `1)` numbers, `#` headings,
  Markdown's backslash rule) and read by `Note`'s one reader. `Clipboard.paste` splices the run
  into the note as a pure function; the editor then replaces only the paragraphs that changed, in
  one undo step.
- **Summaries.** A summary records the fingerprint of the note it describes and the version of
  the prompt that wrote it; it is fresh only while both match. Bumping the prompt version
  therefore regenerates every summary once, and a saved summary without a version counts as
  stale. Spinner, failure and "no key" are derived, not stored as flags.

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
| `paper` | `#F4ECDE` at 78 % | the glass tint of the card body |
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
| `highlight` | `#E8D5AE` | selected text |

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
  item. Sidecar version 2 adds free points and the stack's place; version 1 files, whose slot
  numbers skipped the stack's cell, are shifted by one on load.
- 2026-10-22, overhang and the ribbon toggle: free cards and the stack may hang off the left,
  right and bottom edges, never the top, as long as 40 points of the header strip and the width
  stay reachable. The stack's home moved to the top-right so Pop fills from the top-left;
  version 1 sidecars keep it top-left. Hide all / Show all became a one-click button in the
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
  unsigned debug build.
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
- With no API key, a collapsed card shows "Summary unavailable" with the reason on hover.
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
- Pasted text keeps a backslash that Markdown keeps (`C:\Users`, `a\nb`); only a backslash before
  punctuation escapes it.
