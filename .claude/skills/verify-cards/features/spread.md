# Spread

The stack ribbon's Spread button, a 2 × 2 grid third from the left, lays a new blank card into
each cell ticked in Settings › Spread, the left three cells of the top two rows by default. The
first card has the cursor. The next click gathers those cards into the bottom of the stack, and
the click after puts each back where it was. The button remembers its cards until they are
deleted, across ↩ Stack, Pop and a relaunch. A cell another card or the stack takes is skipped, and
a click that can bring out nothing changes nothing and says why in the tooltip.

## Sub-features

- `spread-first` The first click makes one blank card per ticked cell, in reading order; the first
  has the cursor, and Clarity turns off.
- `spread-face` The button reads `Spread cards` (value `in`) or `Gather cards` (value `out`, accent
  color) while a card of its set is on the desktop.
- `spread-gather` A click with any set card out moves those cards to the bottom of the stack, in
  reading order, and the stack keeps showing the page it showed.
- `spread-back` The click after puts each card back exactly where it last was, a slot or a free
  spot, and gives none the cursor.
- `spread-taken` A card whose place is taken stays in the stack, in the set, and comes out at a
  later Spread once the place is free.
- `spread-refused` With no cell free, or none ticked, nothing changes and the tooltip reads `Your
  Spread cells are taken` or `Pick Spread cells in Settings`.
- `spread-hide-all` Under Hide all, a click shows everything first.
- `spread-fresh` The `New spread` action (Option-click, New Spread in the ⋯ menu) sends the old
  set's desktop cards to the bottom of the stack as ordinary cards and makes a new set.
- `spread-settings` The 5 × 4 grid in Settings, its caption, and the stack's cell, which is dimmed
  and can't be ticked.
- `spread-remap` After a change in Settings, the next Spread moves the set onto the new cells.
- `spread-saved` The sidecar's `spread` holds the cells and each card's place.

## How to get to it (user POV)

- Click the grid icon on the stack's ribbon, third from the left (tooltip `Spread cards` or
  `Gather cards`).
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
- **Refused.** Open Settings with `cv ax key cmd+,`. Press every ticked cell (`cv ax press "Spread
  cell 1"` and so on) until none is ticked; the caption under the grid starts `No cell is ticked`.
  With the set gathered, Spread: `cv ax windows` does not change, and the button's tooltip in `cv ax
  tree` is `Pick Spread cells in Settings`. Now tick only `Spread cell 1`, press New on the stack
  so a card takes that cell, and Spread with the set gathered: still nothing changes, and the
  tooltip is `Your Spread cells are taken`.
- **Settings grid.** In the Settings window's `cv ax tree`, a `Spread` heading follows the Shortcut
  caption, then twenty cells `Spread cell 1` to `Spread cell 20` in reading order. `Spread cell 5`,
  the stack's home, is `[disabled]`. Drag the stack to another cell and bring Settings forward
  again: that cell is now the disabled one.
- **Remap.** Tick only `Spread cell 11` to `Spread cell 13`, close Settings, and Spread with the set gathered: the card
  from the first old place comes out in cell 11, the next in 12 and 13, and the rest stay in the
  stack as ordinary cards (`cv files spread-remap`: `spread.members` has three entries).
- **Fresh.** With some set cards out, run `cv ax act Spread "New spread" stack`. Those cards go to
  the bottom of the stack, and new blank cards fill the ticked cells; the sidecar's `spread.members`
  lists only the new ids.
- **Relaunch.** `cv stop`, then `cv launch --seed <the sidecar from cv files>`: the set is the one
  saved, and a Spread puts its cards back where the sidecar says.

## Gotchas

- `cv ax press Spread` matches the button's name exactly, so it never presses a Settings cell,
  whose names start `Spread cell`. `act` matches by prefix: always give it the `stack` window.
- Blank cards have no first line, so `card=<first line>` cannot address them. Type a header into
  the card with the cursor right after the first Spread, as above.
- The beep that comes with a refused click is not observable here; the tooltip is.
- Opening the ⋯ menu and pressing New Spread inside it was not proved possible with `cards-ax`.
  Prove the fresh path with the `New spread` action, and report the menu item as not driven.
- A Settings cell's role and value in `cv ax tree` were not seen in a live run when this entry was
  written: check how the first `tree` prints a ticked and an unticked cell, and fix this entry.
- Each Spread can write up to six `.md` files (`# ` and a line break) into the scratch folder,
  never the owner's.
