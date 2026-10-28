# Move cards and the stack

A user moves a popped card by dragging its header (or its margin), and moves the stack by
dragging its ribbon's empty space. The screen is an invisible 5 × 4 grid of card-sized slots.
A drop whose center lands within 15% of a cell of a slot's center snaps into that slot. A drop
onto a slot held by another snapped card, or by the stack, swaps the two. Any other drop stays
free exactly where it was released, overlapping whatever is there. A free card or stack may hang
off the left, right and bottom edges, but at least 40 points of it stay on screen, so it can
always be grabbed back.

## Sub-features

- `drag-snap` A drop near a free slot's center snaps into that slot.
- `drag-swap` A drop onto a slot held by another snapped card swaps them: the occupant takes the
  mover's old slot.
- `drag-swap-free` If the mover was free, the occupant goes to the mover's exact free spot.
- `drag-free` A drop farther than 15% of a cell from every slot center stays free at that point.
- `drag-overhang` A free card may hang off the left, right and bottom edges, never the top. A
  drop past the limit lands at the limit, with 40 points still on screen.
- `drag-grab-back` A card at the limit can be dragged back by the strip still on screen.
- `drag-stack` The stack moves the same way by its ribbon: snap, swap with a card, free, back
  home.
- `drag-guide` While the button is down, a guide outlines the slot under the dragged center:
  solid and filled where a drop would snap, dashed where it would stay free.

## How to get to it (user POV)

- Press a popped card's header line (or the margin around its text) and drag. A press that
  doesn't move is an ordinary text click.
- Press the stack's ribbon anywhere that isn't a button, such as the gap between Clarity and
  the Hide all eye, and drag. A press that doesn't move acts as the edge band under it.
- While dragging, a guide outlines the slot nearest the dragged item's center. It is dashed
  while a drop would stay free and solid once a drop would snap.

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- `cv ax windows` lists one window, the stack, at `@1368,34 342x268`.

Frames are `cv ax windows` output on the owner's 1710 × 1107 display (menu bar 34, Dock
auto-hidden). There one cell is 342 × 268.25, windows list as 342x268, and slot `n` is at
`@342*(n%5),34+268*(n/5)` in the top three rows, the only ones used below (the fourth row starts
at 839, because cell edges round to whole points). The stack's `y` in the precondition's
`cv ax windows` is the menu bar's height. If it is not 34, or the display is another size,
recompute every frame below from cell width = screen width / 5 and cell height = (screen height −
menu bar) / 4. Every drag below moves the item by whole cells, plus a small offset where noted.
Wait 1 s after each drag before `cv ax windows`, because the snap animates. Wait 1.5 s before
`cv files`. Each step starts from where the previous one left off. Run `cv shot drag-before`
first.

- **Pop both.** Run `cv ax press "↗ Pop" stack` twice. `cv ax windows` lists Alpha `@0,34`
  (slot 0), Beta `@342,34` (slot 1) and the stack `@1368,34`. The badge reads 0.
- **Snap (`drag-snap`).** Drag Alpha down one row, 10 points right and about 7 down of exact. Run
  `cv ax drag card=Alpha 0.5 0.07 10 275`. Alpha is at `@0,302`, exactly slot 5, not
  `@10,309`. `cv files drag-snap` shows `"card" : "seed-a", "slot" : 5` in `placements`, Beta
  still at `"slot" : 1`, and `"stackSlot" : 4`. The `.md` files are unchanged.
- **Swap (`drag-swap`).** Drag Beta onto Alpha's slot. Run `cv ax drag card=Beta 0.5 0.07 -342
  267`. Beta is at `@0,302` and Alpha has moved to Beta's old `@342,34`. `cv files drag-swap`
  shows `seed-a` at `"slot" : 1` and `seed-b` at `"slot" : 5`.
- **Free (`drag-free`).** Drag Alpha half a cell right and half a cell down, onto the corner
  between four slots. Run `cv ax drag card=Alpha 0.5 0.07 171 133`. Alpha is at `@513,167`
  and stays there. `cv files drag-free` shows `seed-a` with no `slot` and `"free" : { "x" :
  0.4, "y" : 0.2488350419384902 }`, which is its center as a fraction of the area below the menu
  bar: 684 / 1710 across, (301 − 34) / 1073 down.
- **Swap from a free spot (`drag-swap-free`).** Drag the free Alpha onto Beta's slot 5. Run
  `cv ax drag card=Alpha 0.5 0.07 -513 134`. Alpha is at `@0,302` and Beta takes Alpha's exact
  free spot `@513,167`. `cv files drag-swap-free` shows `seed-a` at `"slot" : 5` and `seed-b`
  at `"free" : { "x" : 0.4, "y" : 0.2488350419384902 }`.
- **Overhang (`drag-overhang`).** Drag Alpha by the right margin beside its Delete button,
  toward the bottom-left corner, past the limit. Run `cv ax drag card=Alpha 0.98 0.07 -330
  775`. The pointer ends at about (5, 1096), which would put the card's center at (−159,
  1211). Alpha lands at the limit instead, `@-302,1067 342x268`: 40 points of its width remain
  on the left (−302 + 342) and its top 40 points remain above the bottom edge (1107 − 1067).
  `cv files drag-overhang` shows `seed-a` at `"free" : { "x" : -0.07660818713450293, "y" :
  1.087721342031687 }`.
- **Grab back (`drag-grab-back`).** Drag Alpha by the 40-point strip still on screen. Run
  `cv ax drag card=Alpha 0.97 0.07 302 -1028`. Alpha snaps to `@0,34`. `cv files drag-back`
  shows `seed-a` at `"slot" : 0`. Beta is still free at `0.4, 0.2488350419384902`.
- **Stack to a free slot (`drag-stack`).** Drag the ribbon's gap two columns left and one row
  down. Run `cv ax drag stack 0.5 0.07 -684 267`. The stack is at `@684,302`. `cv files
  stack-snap` shows `"stackSlot" : 7`, and `placements` is unchanged.
- **Stack swaps with a card.** Drag the stack onto Alpha's slot 0. Run `cv ax drag stack 0.5
  0.07 -684 -267`. The stack is at `@0,34` and Alpha has moved to `@684,302`. `cv files
  stack-swap` shows `"stackSlot" : 0` and `seed-a` at `"slot" : 7`.
- **Stack free.** Run `cv ax drag stack 0.5 0.07 171 133`. The stack is at `@171,167`.
  `cv files stack-free` has no `stackSlot` and shows `"stackFree" : { "x" : 0.2, "y" :
  0.2488350419384902 }`.
- **Stack home.** Run `cv ax drag stack 0.5 0.07 1197 -133`. The stack snaps back to
  `@1368,34`. `cv files stack-home` shows `"stackSlot" : 4` and no `stackFree`. Clarity is
  still `value="off"`, and the badge still reads 0. Run `cv shot drag-after` and `cv note
  "drag via cv ax drag: snap, swap, swap-free, free, overhang, grab back, stack"`.
- **Guide (`drag-guide`).** Hold a drag partway with raw mouse events. Alpha is at `@684,302`, so
  (855, 325) is on its header line. Run `cv ax mouse move 855 325` and `cv ax mouse down 855
  325`, then `cv ax mouse drag 855 <y>` for y = 330, 345, 405, 485, 565 and 592 (about one row
  down), then `cv shot drag-guide-snap`. `cv ax windows` lists one more 342x268 window at `@684,570`,
  and its PNG is a solid, filled outline. Run `cv ax mouse drag 1026 458` (half a cell right and
  down) and `cv shot drag-guide-free`: the guide moves to the cell holding the center, `@1026,302`,
  and its PNG is dashed. Drag back in steps to (855, 325) and `cv ax mouse up 855 325`: Alpha
  stays at `@684,302` and the guide window is gone.

## Gotchas

- `cv ax windows` taken right after `drag` can show the frame mid-animation, for example
  `@344,38` while the card is still sliding into `@342,34`. Wait 1 s.
- Pick the press point with care. On a popped card the top-right corner holds the Collapse,
  ↩ Stack and Delete buttons, at about 0.68 to 0.95 of the width. A drag that starts on a
  button moves nothing (and a release back on Delete would ask to delete). Press `0.5 0.07` for
  the header line, or `0.97`–`0.98` for the right margin. On the stack, `0.5 0.07` is the
  ribbon gap; Pop and the card's buttons sit lower, at about 0.2 of the height.
- `drag` moves the real pointer, and the operating system keeps it on screen. To push past the
  overhang limit, press near the far edge of the card, as the overhang step does, so that the
  card's center crosses the limit while the pointer stays on screen.
- The bottom limit sits 40 points above the screen's usable bottom. With the Dock auto-hidden
  that is the screen's edge. With a visible Dock it is the Dock's top, so the overhang `y`
  differs. The left and right limits leave 40 points of width either way.
- Drags change only the sidecar (`placements`, `stackSlot`, `stackFree`). The `.md` files and
  `stack` order stay as they were.
- `cv ax tree` may list a small unnamed window (`w0 @… 84x77` with a `?` child). It is not a
  card, and `cv ax windows` does not list it. Address windows by name.
- The guide shows only while the button is down. `drag` is one atomic gesture, so capture it
  with `mouse down` and `mouse drag` steps, as the Guide step does.
- "Free positions survive relaunch" is not covered here: `cv stop` deletes the run's folder, and
  `cv launch` always starts a new one.
