# Spread

The stack ribbon's Spread button, a 2 × 2 grid third from the left, lays a new blank card into
each cell ticked in Settings › Spread, the left three cells of the top two rows by default. The
first card has the cursor. The next click gathers those cards into the bottom of the stack, and
the click after puts each back where it was. If nothing was typed in any of them, the next click
deletes them instead, with no alert, and the click after makes a new set. The button remembers
its cards until they are deleted, across Return to stack, Pop and a relaunch. A cell another card
or the stack takes is skipped, and a click that can bring out nothing changes nothing and says
why in the tooltip.

## Sub-features

- `spread-first` The first click makes one blank card per ticked cell, in reading order; the first
  has the cursor, and Clarity turns off.
- `spread-face` The button reads `Spread cards` (value `in`), or `Gather cards` or `Delete empty
  cards` (value `out`, accent color) while a card of its set is on the desktop. It reads `Delete
  empty cards` exactly while no card of the set, on the desktop or in the stack, has text.
- `spread-gather` A click with any set card out and some card of the set holding text moves the
  set's desktop cards to the bottom of the stack, in reading order, empty ones too, and the stack
  keeps showing the page it showed.
- `spread-delete` A click with a set card out and no text in any card of the set deletes every card
  of the set, in the stack too, with no alert. The set ends, the stack keeps its page, and the next
  click makes a new set. Option-click never deletes.
- `spread-back` The click after puts each card back exactly where it last was, a slot or a free
  spot, and gives none the cursor.
- `spread-taken` A card whose place is taken stays in the stack, in the set, and comes out at a
  later Spread once the place is free.
- `spread-refused` With no cell free, or none ticked, nothing changes and the tooltip reads `Your
  Spread cells are taken` or `Pick Spread cells in Settings › Spread`.
- `spread-hide-all` Under Hide all, a click shows everything first.
- `spread-fresh` The `New spread` action (Option-click, New Spread in the ⋯ menu) sends the old
  set's desktop cards to the bottom of the stack as ordinary cards and makes a new set.
- `spread-settings` The 5 × 4 grid in Settings, its caption, and the stack's cell, which is dimmed
  and can't be ticked.
- `spread-remap` After a change in Settings, the next Spread moves the set onto the new cells.
- `spread-saved` The sidecar's `spread` holds the cells and each card's place.

## How to get to it (user POV)

- Click the grid icon on the stack's ribbon, third from the left (tooltip `Spread cards`, `Gather
  cards` or `Delete empty cards`).
- Option-click it for a fresh set (not driven: `cards-ax` sends no modifier).
- **New Spread** in the stack ribbon's ⋯ menu (not driven: see Gotchas).
- VoiceOver: the button's `New spread` action.
- Settings… › Spread for the cells: the stack ribbon's ⋯ menu (not driven), the menu bar icon (not
  driven), or ⌘, while Ideator is active.

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`. The stack is in its home cell, top right, and
  shows Alpha.
- A scratch run starts with the factory cells and keeps a change made in Settings until it quits.

- **Spread.** Click Spread. Run `cv ax press Spread stack`. `cv ax windows` lists seven windows,
  the stack and six cards. `cv ax tree` shows the Spread button with `value="out"` and the tooltip
  `Gather cards`. Run `cv ax type 'Spread one'`: it lands in the top-left card, the one with the
  cursor. `cv shot spread-out` shows six cards in the left three cells of the top two rows and the
  grid icon in the accent color.
- **Gather.** Run `cv ax press Spread stack` again. `cv ax windows` lists only the stack, the count
  badge reads `AXButton "8"`, and `cv ax text stack` still prints Alpha's text. The button is back
  to `value="in"`, tooltip `Spread cards`. Wait 1.5 s and run `cv files spread-gathered`: the
  sidecar's `stack` ends with the six new ids, and its `spread` has `"cells" : [0, 1, 2, 5, 6, 7]`
  and one `members` entry per card, each with its `slot`.
- **Spread again.** Run `cv ax press Spread stack`. The same six cells fill again, `card=Spread one`
  in the top-left, and no card gets the cursor.
- **Taken.** Gather, then run `cv ax press New stack` and `cv ax type 'Blocker'`: New takes the
  top-left cell, `Spread one`'s. Spread: `Spread one` stays in the stack (the badge reads 3) and the
  other five come out. Delete the blocker (`cv ax press "Delete this card" card=Blocker`, then `cv ax
  press Delete`), Gather, and Spread once more: `Spread one` comes out in the top-left cell too.
- **A remembered free spot.** Drag `Spread one` by its header until it stays free between cells
  (`cv ax drag "card=Spread one" 0.5 0.04 150 110`), and note its frame in `cv ax windows`. Gather,
  then Spread. `Spread one` comes back with the same frame.
- **Hide all first.** With the set gathered, run `cv ax press "Hide all" stack`, then `cv ax press
  Spread stack`. `cv ax windows` lists the full-size stack and every card, and the toggle is
  `Hide all` again.
- **Refused.** Open Settings with `cv ax key cmd+,`, then `cv ax section Spread`. Press every ticked cell (`cv ax act "Spread
  cell 1" AXPress`, and the same for 2, 3, 6, 7 and 8) until none is ticked; a line under the caption reads `No cell is ticked,
  so Spread makes no card. Tick the cells it should fill.`
  With the set gathered, Spread: `cv ax windows` does not change, and the button's tooltip in `cv ax
  tree` is `Pick Spread cells in Settings › Spread`. Now tick only `Spread cell 1` (the same `act`), press New on the stack
  so a card takes that cell, and Spread with the set gathered: still nothing changes, and the
  tooltip is `Your Spread cells are taken`.
- **Settings grid.** After `cv ax section Spread`, the Settings window's `cv ax tree` has the title `Spread`
  and its lead, then twenty cells `AXCheckBox "Spread cell 1"` to `Spread cell 20` in reading order, five
  columns by four rows at equal steps, 36 points across and 28 down, each 34x26 in `tree` for a
  32 × 24 cell (measured 2026-10-30: x 734, 770, 806, 842, 878 and y 306, 334, 362, 390 on the first
  run). `cv shot` shows the
  ticks, which `tree` does not print. `Spread cell 5`,
  the stack's home, is `[disabled]`. Drag the stack to another cell and bring Settings forward
  again: that cell is now the disabled one.
- **Remap.** Tick only `Spread cell 11` to `Spread cell 13`, close Settings, and Spread with the set gathered: the card
  from the first old place comes out in cell 11, the next in 12 and 13, and the rest stay in the
  stack as ordinary cards (`cv files spread-remap`: `spread.members` has three entries).
- **Fresh.** With some set cards out, `cv ax tree` prints the Spread line with `actions=[New spread]`.
  Run `cv ax act Spread "New spread" stack`. Those cards go to
  the bottom of the stack, and new blank cards fill the ticked cells; the sidecar's `spread.members`
  lists only the new ids.
- **Delete.** Start a fresh run (`cv stop`, `cv launch --seed`), note the badge, click Spread and
  type nothing. `cv ax tree` shows the Spread button with `value="out"` and the tooltip `Delete
  empty cards`. Run `cv ax press Spread stack`: `cv ax windows` lists only the stack, the badge
  reads what it read before the first click, the button is `value="in"` with the tooltip `Spread
  cards`, and after 1.5 s `cv files spread-deleted` shows a sidecar with no `spread` key and only
  the seed's `.md` files. Press Spread once more: six new cards come out in the same cells. Type
  `Written` into the one with the cursor and look at `cv ax tree` again: the tooltip reads `Gather
  cards`, and one click gathers all six.
- **Relaunch.** Gather the set, note the frames of a first Spread (`cv ax windows`), and run `cv files
  NAME`. Then `cv stop`, and `cv launch --seed build/verify-evidence/<run>/NAME-files/.cards.json`,
  which brings the `.md` files beside it. The badge counts every card, the button reads `Spread cards`,
  and one Spread puts the saved cards back in the same frames, with `spread.members` unchanged.

## Gotchas

- `cv ax press Spread` matches the button's name exactly, so it never presses a Settings cell,
  whose names start `Spread cell`, and `cv ax section Spread` presses only the Settings sidebar's row. `act` matches by prefix: always give it the `stack` window for the
  button. A Settings cell is an `AXCheckBox`, which `cv ax press` does not reach (it looks for buttons).
  Press one with `cv ax act "Spread cell N" AXPress`, no window: the prefix `Spread cell 1` finds cell 1
  before cell 10, and `Spread cell 2` finds cell 2 before cell 20.
- Blank cards have no first line, so `card=<first line>` cannot address them. Type a header into
  the card with the cursor right after the first Spread, as above.
- The beep that comes with a refused click is not observable here; the tooltip is.
- Opening the ⋯ menu and pressing New Spread inside it was not proved possible with `cards-ax`.
  Prove the fresh path with the `New spread` action, and report the menu item as not driven.
- `cv ax tree` prints a Settings cell with no ticked state, because `cards-ax` reads only string values.
  Read it from `cv shot` (a check mark in the cell), or from what a Spread does.
- Each Spread can write up to six `.md` files (`# ` and a line break) into the scratch folder,
  never the owner's. A click that deletes them moves each file it saved to the user's real Trash, as
  a Delete does; a click inside the 1 s save delay writes nothing and trashes nothing.
