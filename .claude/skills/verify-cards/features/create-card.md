# Create a card

A user makes a card with New on the stack's ribbon, which pops a blank card into the first free
slot with the caret on its header line, or by typing on the stack's blank page, which turns the
page into a card at the bottom of the stack. The first line becomes the bold header, and each card
is saved as its own Markdown file.

## Sub-features

- `create-new` New pops a blank card into the first free slot, caret on the header line.
- `create-type` Typed text shows in the card; the first line is the header.
- `create-save` The card is saved as `<timestamp>.md` with `# <header>` and the body, and the
  sidecar places it.
- `create-blank-page` Typing on the stack's blank page makes a stacked card and a new blank page
  after it.
- `create-blank-untouched` Leaving the blank page empty makes nothing.

## How to get to it (user POV)

- Click New, the plus icon at the left of the stack's tan ribbon (tooltip `New card`).
- Flip the stack to its blank page (after the last card), click into it and type.
- When the desktop is full, New shows the stack's blank page instead (not driven here).

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- No card is popped (the baseline).

- **New.** Click New. Run `cv ax press New`. `cv ax tree` shows a second window at the top-left
  cell whose `AXTextArea` is empty and `[focused]`, with buttons `Collapse this card`, `↩ Stack`
  and `Delete this card`.
- **Type.** Type a header and body. Run `cv ax type 'Release checklist\nTag and publish'`.
  `cv ax text card=Release` prints `"Release checklist\nTag and publish"`. `cv shot create-new`
  shows `Release checklist` in bold above `Tag and publish`.
- **Saved.** Wait 1.5 s and run `cv files create-new`. A file `<yyyy-MM-dd HHmmss>.md` holds
  `# Release checklist`, a blank line, then `Tag and publish`. The sidecar's `placements` has that
  id with `"slot" : 0`, and `stack` still lists `seed-a`, `seed-b`.
- **Blank page.** Show the blank page and type on it. Run `cv ax click stack 0.015 0.6` (previous
  from the top card wraps to the blank page). `cv ax text stack` prints `""` and the tree has no
  `↗ Pop`, since the blank page has no card buttons (it still lists the formatting bar's five).
  Run `cv ax focus stack`, then `cv ax type 'Gamma card\ngamma body'`.
  `cv ax text stack` prints `"Gamma card\ngamma body"` and the badge, `AXButton "2"` in `cv ax tree`,
  goes to `AXButton "3"`.
- **Blank page saved.** Wait 1.5 s and run `cv files create-blank-page`. A new `.md` holds
  `# Gamma card` and `gamma body`, and the sidecar's `stack` ends with its id.
- **New blank page.** Run `cv ax click stack 0.985 0.6`. `cv ax text stack` prints `""` again:
  a fresh blank page follows the new card.
- **Untouched.** On that blank page type nothing, flip next with `cv ax click stack 0.985 0.6`, and
  run `cv files create-blank-untouched`. The folder has no new `.md` and the badge still reads 3.

## Gotchas

- `type` sends keys to whichever Ideator window is key. After `press New` that is the new card;
  after a flip, the stack has no caret until `cv ax focus stack`.
- File names are the creation time to the second. Two cards made in the same second get ` 2`
  appended; match by content, not by name.
- The header is the first line of the text, not a separate field. `\n` in `type` is Return.
- The saved file is written up to one second after the last key. Read it too early and it is
  missing or holds older text.
