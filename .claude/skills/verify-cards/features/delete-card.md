# Delete a card

The trash button on a card asks "Delete this card?". Delete removes the card and moves its
Markdown file to the Trash; Cancel keeps it. Deleting the stack's shown card shows the one under
it.

## Sub-features

- `delete-confirm` The trash button opens a sheet with `Delete` and `Cancel`.
- `delete-cancel` Cancel leaves the card and its file alone.
- `delete-popped` Delete on a popped card closes its window and its file leaves the folder.
- `delete-stacked` Delete on the stack's shown card shows the next card and lowers the count.

## How to get to it (user POV)

- The trash button on a popped card (fades in on hover).
- The trash button on the stack's shown card.

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- Alpha shows on the stack and the badge reads 2.

- **Ask.** Click trash on the stack's card. Run `cv ax press "Delete this card" stack`.
  `cv ax tree` shows an `AXSheet` with `Delete this card?`, `Its Markdown file moves to the
  Trash.` and buttons `Cancel` and `Delete`. `cv shot delete-ask` shows the sheet.
- **Cancel.** Run `cv ax press Cancel stack`. The sheet is gone, Alpha still shows, and the badge
  reads 2.
- **Delete stacked.** Run `cv ax press "Delete this card" stack`, then `cv ax press Delete stack`.
  `cv ax text stack` prints the Beta card and the badge reads 1.
- **File gone.** Wait 1.5 s and run `cv files delete-stacked`. The folder has `seed-b.md` but no
  `seed-a.md`, and the sidecar's `stack` is `["seed-b"]`.
- **Delete popped.** Continue from Delete stacked, with Beta the only card left. Run `cv ax press
  "Pop this card out" stack`, then `cv ax press "Delete this card" card=Beta` and
  `cv ax press Delete card=Beta`. `cv ax windows` lists only the stack, the stack shows the blank
  page, and after 1.5 s `cv files delete-popped` shows no `.md` files and empty `placements` and
  `stack`.

## Gotchas

- Deleted files go to the user's real Trash, under their seed or timestamp names. That is the
  feature; leave them there and mention it in the report. Nothing under `~/.Trash` can be listed
  from this shell, so prove the move by the file leaving the run's folder.
- The sheet belongs to the card's window. Scope `press Delete` to that window, because `Delete`
  alone could match another card's sheet.
