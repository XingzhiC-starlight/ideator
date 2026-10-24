# Nested lists

A user nests bullet, numbered and checkbox items up to three levels with Tab and Shift-Tab, each
move carrying the item's children. Bullets are `•`, `◦`, `▪` by level, numbers restart at 1 under
each parent, and the card file saves each level as 4 spaces of indent. Enter on an empty nested
item, or Backspace at the start of one, moves it up a level, and one undo takes back each Tab,
Shift-Tab or the tidying a deleted parent causes.

## Sub-features

- `nested-type` Typing `- ` starts a list; Enter continues it at the same level.
- `nested-tab` Tab nests an item under the one above it; the file shows 4 spaces per level.
- `nested-tab-refused` Tab does nothing at the third level, or on a first child with nothing to
  sit under.
- `nested-tab-char` Tab on the header, a plain line or a list's first item types a tab character.
- `nested-shift-tab` Shift-Tab moves an item up and carries its children.
- `nested-enter` Enter on an empty nested item moves it up a level; at the top it ends the list.
- `nested-backspace` Backspace at the start of a nested item moves it up a level.
- `nested-numbers` A nested numbered run restarts at 1 and the parent's count continues.
- `nested-kind` A list button of another kind, or a checkbox click, changes only that line, never
  its children. The button of the line's own kind makes it plain, and its children move up a level.
- `nested-undo` One ⌘Z undoes one Tab; after deleting a parent the child moves up, and one ⌘Z
  brings back both.
- `nested-old-file` A file with 2-space or tab indents loads nested, and is saved with 4 spaces
  once the card is edited.

## How to get to it (user POV)

- Type in any card (popped, or the stack's card): `- `, `1. ` or `[] ` starts a list.
- Tab and Shift-Tab with the caret in an item, or with several items selected.
- Enter or Backspace in an empty nested item.
- The formatting bar's three list buttons, and a click on a checkbox.
- ⌘Z and ⇧⌘Z.

## Driving it with cards-verify

Preconditions:

- `cv launch` (an empty folder is enough); `cv doctor` prints `healthy`.
- `cv ax press New` made a card and the caret is on its header line.

- **Type a list.** Run `cv ax type 'Trip\n- pack\nsocks\nshirts\nbook'`. After 1.5 s,
  `cv files nested-type` shows `- pack`, `- socks`, `- shirts`, `- book` under `# Trip`.
- **Tab nests.** The caret is at the end of `book`. Run `cv ax key up`, `cv ax key up` (socks),
  `cv ax key tab`, `cv ax key down` (shirts), `cv ax key tab`, `cv ax key tab`. `cv files` shows
  `    - socks` and `        - shirts`; `cv shot nested-tab` shows `◦ socks` and `▪ shirts`.
- **Tab refused.** With the caret still on shirts (level 3), run `cv ax key tab`; then
  `cv ax key up` (socks, a first child) and `cv ax key tab`. The file is unchanged and
  `cv ax text card=Trip` has no tab character.
- **Undo a Tab.** Run `cv ax key cmd+up` then `cv ax key down` three times (shirts),
  `cv ax key shift+tab`, `cv ax key tab`, `cv ax key cmd+z`. The file shows shirts back at 4
  spaces; `cv ax key shift+cmd+z` puts it at 8 again.
- **Shift-Tab carries children.** `cv ax key cmd+up`, `cv ax key down` twice (socks), then
  `cv ax key shift+tab`. The file shows `- socks` with `    - shirts` under it.
- **Enter on an empty nested item.** `cv ax key down` (shirts), `cv ax key cmd+right`,
  `cv ax key return`: the file gains `    - ` (an empty level-2 item). `cv ax key return` again:
  it becomes `- ` at the top, and no new line is added.
- **Tab types a tab.** `cv ax key cmd+down`, `cv ax key return` twice (the second ends the
  list), `cv ax type 'notes'`, `cv ax key cmd+left`, `cv ax key tab`. `cat -vet` on the saved
  file shows `^Inotes`.
- **Numbers per parent.** `cv ax press New`, `cv ax type 'Plan\n1. Day one\nflight\nhotel\nDay two'`,
  `cv ax key up` twice (flight), `cv ax key tab`, `cv ax key down`, `cv ax key tab`. The file
  shows `1. Day one`, `    1. flight`, `    2. hotel`, `2. Day two`, and the shot shows the same
  numbers.
- **Delete a parent, then undo.** `cv ax key cmd+up`, `cv ax key down`, `cv ax key cmd+left`,
  `cv ax key shift+down` selects `Day one`'s line; `cv ax key delete`. The file shows
  `1. flight` at the top with `    1. hotel` under it. One `cv ax key cmd+z` brings back
  `1. Day one` with flight and hotel nested again.
- **Backspace.** Put the caret at the start of flight with `cv ax key cmd+up`, `cv ax key down`
  twice and `cv ax key cmd+left`, then `cv ax key delete`. flight moves to level 1: the file shows
  `1. Day one`, `2. flight`, `    1. hotel`, `3. Day two`. `cv ax key cmd+z` undoes it.
- **The bar.** `cv ax key cmd+up`, `cv ax key down`, `cv ax key cmd+right` (the caret on Day one,
  nothing selected), then `cv ax press "Bulleted list"`. Only that line changes: `- Day one` over
  `    1. flight`, `    2. hotel`, and `Day two` renumbers to `1.`. `cv ax key cmd+z`. Pressing
  `"Numbered list"` there instead, the line's own kind, makes `Day one` plain and lifts flight and
  hotel a level (`1. flight`, `    1. hotel`).
- **Checkbox.** `cv ax press New`, `cv ax type 'Boxes\n[] parent\nchild'` (a list never starts
  in the header, so the title comes first) and `cv ax key tab`. Click the parent's box with
  `cv ax click card=Boxes FX FY`, reading FX and FY off a `cv shot` (on the owner's display
  `0.092 0.18`: the box is 31.5 points in from the card's left edge at level 0). The file shows
  `- [x] parent` and `    - [ ] child`.
- **Old file.** While the app runs, write a `.md` into the run's folder (`source
  build/verify-runs/current.env; printf ... > "$FOLDER/old.md"`) with 2-space and tab indents.
  Activate another app (`osascript -e 'tell application "Finder" to activate'`), then
  `cv ax click stack 0.5 0.03` so Ideator rescans. The new card joins the bottom of the stack. After a
  plain `cv launch` the stack was empty and showed its blank page, so it now shows the new card
  with no flip; from a seeded launch, run `cv ax click stack 0.985 0.6` until it shows. `cv ax
  text stack` shows its lines and `cv shot` shows them
  nested. `cv ax focus stack`, `cv ax key cmd+down`, `cv ax type '!'`: the file now has 4 spaces
  per level, and an indented plain line keeps its spaces.

## Gotchas

- `up` and `down` keep the caret's x position, and items at different levels start at different
  x. Moving down from an indented item into a shallower one lands inside its text, so a
  `shift+down` selection can touch a line you meant to stop before. Start selections at the
  shallower line, or check the selection with `cv shot` before copying.
- After `cmd+z` the undone lines can stay selected, and a list button then changes every line in
  the selection. Move the caret (`cmd+right`) before pressing a button.
- ⌘ shortcuts (⌘Z, ⌘C, ⌘V) only work while Ideator is the active app; `cv ax key` activates it
  first for any `cmd+` combo. Plain keys (`tab`, `return`, arrows) reach it without that.
- An empty last list item keeps its shape only while the caret is in it. The file shows it, but
  after a relaunch it shows as plain, and takes the shape of the line above once the caret enters
  it. Undoing typing in it can show that inherited shape too, until the next undo.
- The card being edited shows the formatting bar only while Ideator is active; a shot taken right
  after `type` may not show it.
