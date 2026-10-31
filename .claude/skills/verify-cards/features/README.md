# Ideator verification map

This folder is where the recipes for verifying what Ideator users see are kept up to date. Read this
index before driving the app, then use the matching feature file as the recipe. `cv` is shorthand
for the script path in [../SKILL.md](../SKILL.md); type the path itself in every command.

## Baseline preconditions

- `cv build` ran after the last source change, and `cv doctor` prints `healthy`.
- The run was started with `cv launch --seed` unless the recipe says plain `cv launch`. Seeded, the
  stack holds `Alpha card` (body `alpha body`) on top and `Beta card` (body `beta line one`,
  `beta line two`) under it, the count badge reads 2, Clarity is off, and no card is popped.
- The stack window is in its home slot, the top-right cell of the screen.
- Never drive an Ideator instance that `cv launch` did not start.

## Driving conventions

- Start every recipe from the baseline state. Recipes that change state say so; when two recipes
  run in one launch, run the second from whatever the first left, or `cv stop` and relaunch.
- Address windows as `stack` or `card=<first line>`, never by `w` index.
- Prefer `cv ax press` (by button name) over `click` at coordinates. Use `click`, `scroll` and
  `drag` only for the edge bands, swipes and drags, which have no button.
- Wait 1.5 s after the last change before `cv files`: saves are debounced by one second.
- Treat every command as literal. Keep quoted names, including `Return to stack` and
  `Pop this card out`, as written.

## Proof and skip reporting

- Capture the action and the resulting state: `cv shot <feature>-before` and `cv shot
  <feature>-after`, or the `cv ax tree` lines before and after.
- Anything that should persist needs `cv files <feature>` showing the `.md` text and the sidecar
  fields that changed.
- Record the feature ID and the entry point used with `cv note "<feature-id> via <entry>: <what
  you saw>"`.
- Report an entry point you could not drive (the menu bar icon, the global shortcut, a real trackpad swipe) as
  not verified, with the reason. Do not count it as verified through another entry point.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing what the user sees and can
do. It then has exactly four H2 sections, in this order:

1. `Sub-features`: short IDs, one line each.
2. `How to get to it (user POV)`: every user entry point.
3. `Driving it with cards-verify`: starts with `Preconditions:`, then labeled bullets that pair
   each user action with an exact command and the observable result.
4. `Gotchas`: traps that can waste or invalidate a run.

Keep implementation details out of the map. Name only user paths, stable handles, required state,
commands and observable proof.

## Features

- [Create a card](./create-card.md): New from the ribbon, typing the header and body, typing on
  the stack's blank page, and the Markdown file each makes.
- [Browse the stack](./stack-loop.md): next and previous by edge band and swipe, the blank page in
  the loop, Pop, Return to stack and the count badge.
- [Hide all](./hide-all.md): the ribbon's Hide all / Show all toggle, the ribbon-only stack, and
  New while hidden.
- [Spread](./spread.md): the ribbon's Spread button that lays blank cards into the cells ticked
  in Settings, gathers them into the stack and puts them back (or deletes them while none has any
  text), the refusal tooltips, the fresh set, the Settings grid and the set the sidecar saves.
- [Arrange the stack](./arrange-stack.md): the count badge's popover that lists the stacked cards,
  reorders them by grip drag, ⌥↑ and ⌥↓ or VoiceOver actions, and shows one on the stack.
- [Clarity](./clarity.md): the one global Clarity switch, what turns it off (a click on a collapsed
  card, New, typing on the blank page), and what a collapsed card shows.
- [API key](./api-key.md): the Settings field for an Anthropic or an OpenAI key, the lines that name
  its company, and the HTTP 401 a refused key leaves on a collapsed card.
- [First launch](./first-launch.md): the welcome window and the folder it keeps closed until its button,
  the nine-page tour with its rings, waits, Back and Skip, and Settings: its six sections, ⌘W, the
  shortcut recorder, the update controls and the privacy page.
- [Updates](./updates.md): Check Now and Sparkle's windows, the refused forged feed and disk image,
  and the install that relaunches as the next build, proved by `scripts/verify-update.sh`.
- [Delete a card](./delete-card.md): the trash button, its confirmation, and the file leaving the
  folder.
- [Move cards and the stack](./drag.md): dragging a card or the stack to snap, swap, stay free
  between slots, or hang off a screen edge, and the places the sidecar saves.
- [Card buttons on hover](./hover-buttons.md): the buttons that fade in over a card, what a click
  reaches while they are hidden, Show all, Pop and snaps under a resting pointer, and the room a
  long title leaves them.
- [Nested lists](./nested-lists.md): typing lists, Tab and Shift-Tab, Enter and Backspace on
  nested items, numbering per parent, undo, and the 4-space indents in the file.
- [Saving fails](./save-failure.md): the alert at the first failed save, the question at quit while
  saves still fail, the silent quit once the folder is writable again, and a newer sidecar left
  alone mid-run.
- [Copy and paste](./clipboard.md): Markdown and HTML on copy, pasting HTML lists and terminal
  text, one-line and header pastes, and undoing a paste, with the owner's clipboard restored.
- [AI tools (MCP)](./ai-tools.md): `add_card` through the real helper, Top and Bottom, typing in
  the stacked card, Hide all, the off switch, the 1 MB backstop, the background start, the
  welcome window, and Settings › MCP: the instruction box and the Connect an AI tool copy buttons.

Not mapped yet: bold and italic, summaries with a real key, the menu bar icon,
and folder changes made outside the app.
