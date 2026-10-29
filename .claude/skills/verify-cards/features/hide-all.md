# Hide all

Hide all puts every popped card away and shrinks the stack to its tan ribbon, which stays where
the stack is. The ribbon's chevron button, second from the left, toggles between Hide all (pointing
up) and Show all (pointing down) in one click. While
hidden, New still works and shows only the card it brings out. There is no Pop then: its button
is on the stacked card, which hidden removes.

## Sub-features

- `hide-toggle` The ribbon's chevron button hides everything, then shows everything again.
- `hide-ribbon` While hidden the stack is just its ribbon, with the New, Show all, Spread and Clarity icons
  on the left, the count badge left of the ⋯ menu on the right, and no `Pop this card out`.
- `hide-new` New while hidden shows only the new card.
- `hide-show` Show all brings back the stack's card and every popped card.

## How to get to it (user POV)

- The chevron button in the stack's ribbon (tooltip `Hide all`, then `Show all`).
- The menu bar icon's Show All / Hide All (not driven by this skill).
- The global shortcut anywhere, ⌃⌥I by default (not driven: a scratch run does not register it).
- Opening Ideator again from Finder or Spotlight shows everything (not driven).

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- One card popped: run `cv ax press "Pop this card out" stack`. `cv ax windows` lists two windows, both
  342x268 on the owner's display.

- **Hide.** Click the chevron button. Run `cv ax press "Hide all" stack`. `cv ax windows` lists one
  window, the stack, now only ribbon-high (`342x46` on the owner's display). `cv ax tree` shows
  `Show all` where `Hide all` was, no `AXTextArea`, no `Pop this card out`, and the count badge
  (`AXButton "1" | "1 card in the stack"`, tooltip `Arrange the stack`: Beta is the only stacked
  card) inside the ribbon, left of `Settings and quit`.
  `cv shot hide-ribbon` shows the tan strip only, its chevron pointing down.
- **New while hidden.** Click New. Run `cv ax press New`, then `cv ax type 'Shown alone'`.
  `cv ax windows` lists the ribbon and one new card. The popped Alpha card stays hidden.
  `cv ax text card=Shown` prints `"Shown alone"`.
- **Show.** Click the chevron button again. Run `cv ax press "Show all" stack`. `cv ax windows` lists
  three full-size windows (the stack, Alpha, Shown alone) and the button is `Hide all` again.
  `cv shot hide-show` shows all three.
- **Not persisted.** Wait 1.5 s and run `cv files hide-all`. The sidecar has no hidden flag, and
  both popped cards are in `placements`.

## Gotchas

- Hidden windows drop out of `cv ax tree` and `cv ax windows` entirely. Prove "hidden" with
  `windows`, since screenshots of a hidden window cannot be taken.
- The toggle button's name changes with the state. `press "Hide all"` fails while hidden; that
  failure is itself evidence of the state.
- Do not use the global shortcut to prove this feature: a scratch run does not register it.
