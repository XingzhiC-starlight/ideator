# Card buttons on hover

Each card's buttons (refresh summary on a collapsed card with two or more body lines, collapse or
expand, ↩ Stack or ↗ Pop, delete) sit in its top-right corner and fade in while the pointer is over
the card, on a popped card and on the stack's card. While they are hidden, a click there is a click on the card: it puts
the caret at the end of the title, and on a collapsed card it is a header press. A card that
appears or moves under a pointer that rests (Show all, Pop, a snap) shows or hides them without a
mouse move. VoiceOver still lists and presses them while they are hidden. A long title wraps, or
truncates when collapsed, before the buttons, never under them.

## Sub-features

- `hover-hidden-click` With the pointer away, a click at the Delete button's point does not ask
  "Delete this card?". The caret goes to the end of the title.
- `hover-show` Moving the pointer onto the card shows the buttons, and the same click then asks.
- `hover-show-all` Show all with the pointer resting where a hidden card's Delete button will be
  shows that card's buttons, so the click acts on a button the user can see.
- `hover-pop` A card that Pop puts under the resting pointer shows its buttons.
- `hover-snap` A snap that moves a card away from the pointer hides its buttons, and one that moves
  the stack's card under the pointer shows them.
- `hover-press` `cv ax press` reaches a hidden button.
- `hover-title` A 40-character title stays clear of the buttons, expanded and collapsed, on a
  popped card and on the stack.

## How to get to it (user POV)

- Move the pointer over a popped card or the stack's card.
- Show all from the ribbon, the menu bar icon or the global shortcut while the pointer rests over
  a hidden card's place.
- ↗ Pop while the pointer rests over the first free slot.
- Drag a card or the stack so it snaps.
- Type a long first line, then collapse the card.

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- Points below are for a 1710 × 1107 display with a 34-point menu bar, where slot 0 is
  `@0,34 342x268`. On another display read them with `cv ax where` and `cv ax windows`.
- `cv shot` captures windows without the pointer. Record where you parked it with `cv note`.

- **Pop Alpha.** Run `cv ax press "↗ Pop" stack`. Alpha is at `@0,34`, and `cv ax tree` lists its
  `Delete this card` at `@310,47 16x11`, so its center is `318 53`.
- **Hidden click (`hover-hidden-click`).** Run `cv ax mouse move 900 700`, wait 1 s, then
  `cv shot hover-off`: Alpha shows no buttons. Run `cv ax mouse down 318 53` and `cv ax mouse up
  318 53`. `cv ax tree` has no `AXSheet`, and Alpha's `AXTextArea` is `[focused]`. To see where the
  caret went, `cv ax type 'X'` gives `"Alpha cardX\nalpha body"`; undo it with `cv ax key cmd+z`.
- **Hover (`hover-show`).** Run `cv ax mouse move 900 700`, then `cv ax mouse move 318 53`, wait
  0.5 s, and `cv shot hover-on`: Collapse, ↩ Stack and Delete show. The same `mouse down` and
  `mouse up` at `318 53` open the sheet `Delete this card?`. Run `cv ax press Cancel`.
- **Show all (`hover-show-all`).** Run `cv ax press "Hide all" stack`; `cv ax windows` lists only the
  ribbon, `@1368,34 342x46`. Run `cv ax mouse move 300 300` and `cv ax mouse move 318 53`, then
  `cv ax press "Show all" stack`, which does not move the pointer. Wait 1 s and `cv shot
  hover-show-all`: Alpha shows its buttons. A `mouse down` and `mouse up` at `318 53` open
  `Delete this card?`. Run `cv ax press Cancel`.
- **Pop under the pointer (`hover-pop`).** Run `cv ax mouse move 660 53` (slot 1's Delete point,
  empty desktop), then `cv ax press "↗ Pop" stack`. Beta arrives at `@342,34`, and `cv shot
  hover-pop` shows Beta's buttons and none on Alpha.
- **Snap away (`hover-snap`).** Run `cv ax mouse move 660 53`, then `cv ax dragat 171 296 0 35`,
  which drags Alpha by its bottom margin 35 points down. It snaps back to `@0,34`, and the pointer
  is left 29 points below it. Wait 1 s; `cv shot hover-snap-away` shows Alpha with no buttons.
- **Snap under (`hover-snap`).** Put Beta back on the stack with `cv ax press "↩ Stack" "card=Beta
  card"`. Run `cv ax mouse move 1539 72` (the ribbon's gap, near its bottom edge) and `cv shot
  hover-stack-before`: Beta on the stack shows no buttons. Run `cv ax dragat 1539 72 0 302`: the
  stack lands 34 points below slot 9 and snaps up to `@1368,302`, which puts the pointer 29 points
  into the card area. Wait 1 s; `cv shot hover-stack-under` shows Collapse, ↗ Pop and Delete.
- **Accessibility (`hover-press`).** Run `cv ax mouse move 900 700`. `cv ax tree` still lists
  Alpha's three buttons, and `cv ax press "Collapse this card" "card=Alpha card"` collapses Alpha.
  Run `cv ax press "Expand this card" "card=Alpha card"` to undo it.
- **Long title (`hover-title`).** Run `cv ax press New stack` and `cv ax type 'Everything to
  finish before the holidays\nline one\nline two'`. The card is at `@342,34`. Run `cv ax mouse
  move 610 140` and `cv shot hover-title-expanded`: the title wraps after "finish", left of
  Collapse. Run `cv ax press "Collapse this card" "card=Everything to finish before the
  holidays"`, hover again, and `cv shot hover-title-collapsed`: the title ends in `…` left of
  Refresh, and `cv ax tree` shows the title's static text ending before `Refresh summary` starts.
  For the stack, run `cv ax press "↩ Stack" "card=Everything to finish before the holidays"` and
  `cv ax press "Expand this card" stack`, hover the stack's card, and take the same two shots.

## Gotchas

- `cv ax click`, `focus`, `drag` and `dragat` send a mouse move first, so the buttons under them
  show before the press. To click without a move, use `cv ax mouse down` and `cv ax mouse up` at a
  point.
- `cv ax press` never depends on hover. It cannot prove that a click acts or does not act.
- `cv ax where "Delete this card"` returns the first card in the tree, which follows the z-order
  and changes after a press. Check the point against `cv ax windows`, or read the button's frame in
  `cv ax tree`.
- A click at a hidden button's point activates Ideator and leaves the caret in the title, so text
  typed next goes into the title.
- The pointer is shared with the person at the Mac. A real mouse move during a step decides hover
  too; if a result looks wrong once, repeat the step before you trust it.
- The fade takes 0.15 s. Wait at least 0.5 s after a move, a press or a drop before `cv shot`.
