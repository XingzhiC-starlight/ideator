# Hide all

Hide all puts every popped card away and shrinks the stack to its tan ribbon, which stays where
the stack is. The ribbon's eye button toggles between Hide all and Show all in one click. While
hidden, New still works and shows only the card it brings out. There is no Pop then: its button
is on the stacked card, which hidden removes.

## Sub-features

- `hide-toggle` The ribbon's eye button hides everything, then shows everything again.
- `hide-ribbon` While hidden the stack is just its ribbon, with New, Clarity, Show all and the ⋯
  menu, and no `↗ Pop`.
- `hide-new` New while hidden shows only the new card.
- `hide-show` Show all brings back the stack's card and every popped card.

## How to get to it (user POV)

- The eye button in the stack's ribbon (tooltip `Hide all`, then `Show all`).
- The menu bar icon's Show All / Hide All (not driven by this skill).
- The global shortcut anywhere, ⌃⌥I by default (not driven: a scratch run does not register it).
- Opening Ideator again from Finder or Spotlight shows everything (not driven).

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- One card popped: run `cv ax press "↗ Pop" stack`. `cv ax windows` lists two windows, both
  342x267 on the owner's display.

- **Hide.** Click the eye button. Run `cv ax press "Hide all" stack`. `cv ax windows` lists one
  window, the stack, now only ribbon-high (`342x46` on the owner's display). `cv ax tree` shows
  `Show all` where `Hide all` was, no `AXTextArea`, no `↗ Pop`, and the count badge
  (`AXButton "1" | "1 card in the stack"`, tooltip `Arrange the stack`: Beta is the only stacked
  card) inside the ribbon.
  `cv shot hide-ribbon` shows the tan strip only.
- **New while hidden.** Click New. Run `cv ax press New`, then `cv ax type 'Shown alone'`.
  `cv ax windows` lists the ribbon and one new card. The popped Alpha card stays hidden.
  `cv ax text card=Shown` prints `"Shown alone"`.
- **Show.** Click the eye button again. Run `cv ax press "Show all" stack`. `cv ax windows` lists
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
