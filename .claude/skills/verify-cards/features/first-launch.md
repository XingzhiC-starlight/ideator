# First launch

The first time Ideator starts on a Mac it shows a welcome window, "Welcome to Ideator", before it touches the notes folder. The welcome says that notes are Markdown files in `~/Documents/Ideator` and that macOS asks for the Documents folder next, that Ideator asks GitHub once a day for updates and asks before it installs one, and that AI is optional and needs the reader's own key, which is the only way a card's text leaves the Mac. Start the tour, or Return, opens the stack and begins a nine-page tour on the real desk. Skip the tour opens the stack and goes to the tour's last page. Each tour page points at a real control with a ring, and a page that asks for a click waits for it. Settings has the shortcut recorder, the update controls and a page on what leaves the Mac, each in its own section.

## Sub-features

- `welcome-card` The welcome shows its text, Start the tour and Skip the tour, and no stack.
- `welcome-gate` The notes folder stays closed until a button; Start the tour and Return both open it and begin page 1.
- `welcome-scratch` A scratch run shows no welcome on its own, and a forced one saves nothing.
- `tour-page-1` The stack, ringed, with Next.
- `tour-page-2` New, ringed, waits for a click on New. Then a text beside the new card.
- `tour-page-3` Hide all, then Show all, each waiting for its real click.
- `tour-page-4` The reader's card shows its hover buttons, and the page waits for Return to stack or Delete.
- `tour-page-5` Below the stack, with Next always.
- `tour-page-6` OPTIONAL. Spread, then Gather, each waiting for its real click, with the free ticked cells lit.
- `tour-page-7` OPTIONAL. Clarity, ringed.
- `tour-page-8` OPTIONAL. The ⋯ menu button, ringed.
- `tour-page-9` Back and Start using Ideator, and no Skip the tour.
- `tour-back` Back is on every page. From page 1 it shows the welcome again, and its Start the tour begins page 1 again.
- `tour-skip` Skip the tour, on the welcome and on a page, goes to page 9.
- `tour-follow` The panel follows the stack when the stack is dragged.
- `tour-replay` Show the Tour restarts the tour at page 1 (not driven).
- `settings-sections` Settings opens on Shortcut, shows one section at a time from the sidebar,
  closes with ⌘W, and opens on Shortcut again.
- `settings-shortcut` The shortcut button records a new combination, refuses an illegal one by name,
  and goes back to the default.
- `settings-updates` The update controls are dimmed in a build that never checks, and the caption
  says why.
- `settings-privacy` The Privacy section's card says the two things that leave the Mac, and nothing else does.

## How to get to it (user POV)

- A fresh install: the welcome appears at launch. The owner can see it and the tour again with
  `defaults delete com.systemlabs.Ideator TourSeen`, or by launching with `CARDS_SHOW_WELCOME=1` in the
  environment. `defaults delete` takes one key, so clearing `WelcomeSeen` too is a second command.
- Show the Tour: in the menu bar icon's menu and in the stack ribbon's ⋯ menu, above **Settings…** (not driven).
- Settings: **Settings…** in the menu bar icon's menu or the stack ribbon's ⋯ menu (not driven), or
  ⌘, while Ideator is active.

## Driving it with cards-verify

Preconditions:

- `cv build` ran after the last source change.
- `cv launch --welcome` for the welcome and tour recipes. Add `--seed` for `welcome-gate` only. The welcome
  shows in a scratch run only because `--welcome` forces it, and its buttons save nothing there. Start the
  tour walk (`tour-page-1` to `tour-page-9`) on an unseeded run, so the stack starts empty and page 6 counts
  the six factory cells, the left three of the top two rows.
- The tour recipes run in order in one launch, and each starts from where the one before left the tour.
  After each page's check, run `cv shot tour-page-N`.
- Plain `cv launch` for the `settings-*` recipes is enough, and so is the welcome.

- **welcome-card.** Run `cv launch --welcome`. `cv ax tree` lists the text "Welcome to Ideator", the intro,
  three paragraphs that start `Your notes are files.`, `Updates come from GitHub.` and `AI is optional.`,
  `AXButton "Start the tour"` and `AXButton "Skip the tour"`, and no `New`, `Continue` or `Next`. `tree`
  prints only a value's first 120 characters, so read the paragraphs' ends in `cv shot welcome`, the proof
  image. `cv ax windows` lists one window, 446 points wide, centered on the screen.
- **welcome-gate.** Run `cv launch --welcome --seed`. Before a button, `cv ax windows` lists one window and
  `cv ax tree` has no `New` and no count badge: the seeded cards have not been read. Run `cv ax press
  "Start the tour"`. The welcome window is gone, and `cv ax tree` shows `New`, the badge `"2"` (Alpha and
  Beta, now loaded) and the tour panel's `Next`, under the title `The stack holds your cards`. Then `cv
  stop`, launch again the same way, and run `cv ax key return` instead of the press: the same result, which
  proves Return is Start the tour.
- **welcome-scratch.** Run `defaults export com.systemlabs.Ideator - 2>/dev/null | shasum` (empty output
  when the domain is absent, so the hash is stable). Run `cv launch --welcome`, `cv ax press "Start the
  tour"`, `cv stop`, then plain `cv launch` (it waits for `New`, so it fails if a welcome shows), then `cv
  stop`. Run the `shasum` again: equal. Repeat once with `cv ax press "Skip the tour"` in place of the
  Start button: equal again.
- **tour-page-1.** Run `cv launch --welcome`, then `cv ax press "Start the tour"`. `cv ax tree` lists `1 of 9`,
  the title `The stack holds your cards`, a body that starts "The tan strip is its ribbon", and the buttons
  `Skip the tour`, `Back` and `Next`. It has no `OPTIONAL`. `cv ax windows` lists the stack, the panel (322
  points wide) to the left of the stack, and the overlay (as large as the screen). `cv shot tour-page-1`
  shows the panel with its notch pointing right at the ribbon, and the overlay's PNG holds the ring around
  the whole stack.
- **tour-page-2.** Run `cv ax press Next`. `cv ax tree` lists `2 of 9`, a title that ends `on the stack` (the
  plus before it is a drawn chip), a body that starts "One new card appears at the top left", and `Skip the
  tour` and `Back`, and no `Next`. `cv shot tour-page-2` shows the ring around New. Now run `cv ax press
  New`. A card appears at the top left, and the title becomes `Type or paste into your card`, with `Next`
  back and the panel to the right of that card. Run `cv ax type 'Tour card'`: the caret is on the new card's
  header line. `cv shot tour-page-2-card`.
- **tour-page-3.** Run `cv ax press Next`. The title ends `to hide every card`, the body starts "Your card and
  the stack's page go away; only the ribbon stays." and names `⌃⌥I`, and there is no `Next`. The ring is
  around the Hide all button. Run `cv ax press "Hide all"`. The title ends `to bring them back`, and the body
  starts "Nothing was deleted; the cards are only hidden." `cv ax windows` lists the stack 46 points high, the
  panel and the overlay, and no card window. The panel stays to the left of the ribbon, which keeps its ring.
  Run `cv ax press "Show all"`. The title is `Hidden, not deleted: all back`, the body is "Use it whenever
  the cards are in your way.", `Next` is back, and `cv ax windows` lists the full stack and `Tour card` again.
- **tour-page-4.** Run `cv ax press Next`. The title starts `Hover your card, click` (the Return icon follows
  it), there is no `Next`, and `cv shot tour-page-4` shows the card's top-right buttons visible without a
  pointer over the card, and a ring around them. `cv ax tree` lists those buttons whether they show or not,
  so the image is the proof. Run `cv ax press "Return to stack" "card=Tour card"`. The title is `Your card
  is in the stack`, the ring moves to the whole stack, `Next` is back, the body ends "type on it to add a
  card.", the badge reads `"1"`, and `cv ax windows` no longer lists the card. For the other ending, start
  again from `cv stop` and `cv launch --welcome`, go to this page the same way, then run `cv ax press
  "Delete this card" "card=Tour card"` and `cv ax press Delete`. The title is `Your card is deleted` and the
  body starts "Cards you return instead stay in the stack."
- **tour-page-5.** Run `cv ax press Next`. The title is `Your cards follow you`, the body starts "Swipe to
  another Space or open a full-screen app", `Next` is there, and no ring is drawn. `cv ax windows` lists the
  panel below the stack, with its right edge level with the stack's. Its three reactions need a Space change,
  another app in front and the cards coming forward again, so they are not driven (see Gotchas).
- **tour-page-6.** Run `cv ax press Next`. `cv ax tree` lists `6 of 9`, then `OPTIONAL`. The title ends
  `Spread: 6 blank cards`, and there is no `Next`. `cv shot tour-page-6` shows the ring around Spread, and the
  overlay's PNG shows six lit cells, the left three of the top two rows, with a dashed light outline. Run `cv ax
  press Spread`. Six blank cards come out (`cv ax windows` lists six card windows more than before), the title
  ends `again to put them away`, the body starts "Blank cards vanish.", and `OPTIONAL` is gone. Run `cv ax press
  Spread` again. No card has text, so the click deletes the set. The title is `Gone, nothing was kept` and
  `Next` is back. For the other ending, run `cv ax press Back` (page 5) and `cv ax press Next` (page 6 asks for
  Spread again), then `cv ax press Spread`, `cv ax type 'Kept'` (the first new card has the cursor) and `cv ax
  press Spread`. The title is `In the stack, back in one click` and the six cards are in the stack.
- **tour-page-6-off.** From page 5 (press Back from page 6 to get there), open Settings with `cv ax key cmd+,`
  and `cv ax section Spread`. Untick the six cells with `cv ax act "Spread cell 1" AXPress`, and the same for 2,
  3, 6, 7 and 8. Close Settings with `cv ax key cmd+w`, then run `cv ax press Next`. The title is `Spread is
  off`, the body ends "None are ticked, so the button does nothing right now.", `Next` is there, and there is
  no `OPTIONAL`. `cv shot tour-page-6-off` shows Spread ringed and no cell lit.
- **tour-page-7.** From the end of page 6, or from `Spread is off`, run `cv ax press Next`. `cv ax tree` lists `7
  of 9`, `OPTIONAL`, a title that ends `Clarity: a summary per card`, a body that starts "Every card shows its
  title and a one-line summary", and `Next`. The ring is around `Clarity`.
- **tour-page-8.** Run `cv ax press Next`. The title is `Your AI tool can add cards`, `OPTIONAL` follows `8 of
  9`, and the body starts "In Claude Code or Claude Desktop, say". The ring is around the ⋯ menu button, named
  `Settings and quit`.
- **tour-page-9.** Run `cv ax press Next`. The title is `Done: replay from the menu bar`. `cv ax tree` lists `9
  of 9`, `Back` and `Start using Ideator`, and no `Skip the tour`, `Next` or `OPTIONAL`. `cv shot tour-page-9`
  shows the panel left of the stack and top-aligned with it, and the overlay's PNG has a ring in the menu bar
  strip, where the menu bar icon is. Run `cv ax press "Start using Ideator"`. The tour ends: `cv ax windows`
  lists no panel and no overlay, and `cv ax tree` has no `Back`. The press also opens the run's folder in
  Finder and brings Finder forward, which moves the owner's front app, so make it the last step of a launch.
  Close that Finder window yourself. Return presses the button too when the panel is the key window. To prove
  that, run `cv ax key return` in place of the press, and report it if nothing happens.
- **tour-back.** Run `cv stop`, then `cv launch --welcome` and `cv ax press "Start the tour"`, so that no card
  of the reader's is out. Run `cv ax press Back` on page 1. `cv ax tree` lists `Start the tour` and `Skip the
  tour` once each, and no `Next`, no `Back` and no `n of 9`: the panel and the overlay are ordered out, not
  covered. `cv ax windows` lists the stack and the 446-point welcome, and no 322-point panel. Run `cv ax press
  "Start the tour"`: page 1 is back. Then walk back from the end. Run `cv ax press "Skip the tour"` on the
  panel, which goes to page 9, then `cv ax press Back` once per page and read each title: `Your AI tool can add cards`,
  `Clarity: a summary per card`, `Spread, then Gather`, `Your cards follow you`, `The stack holds your cards`
  (page 4, with no card of the reader's out) and `Hidden, not deleted: all back`. One more Back shows page 2
  with a title that ends `makes one card`, since there is no card of the reader's.
- **tour-skip.** Run `cv stop`, then `cv launch --welcome`, then `cv ax press "Skip the tour"` on the welcome.
  The stack appears and the panel's title is `Done: replay from the menu bar`, page 9. Run `cv stop` and `cv
  launch --welcome` again, press `Start the tour`, and on page 1 run `cv ax press "Skip the tour"`: the same
  page 9. On page 2 the same press works too, although that page waits. Page 9 has no such button.
- **tour-follow.** On page 1, note the stack and the panel in `cv ax windows`. Run `cv ax drag stack 0.5 0.07
  -342 267`, wait 1 s, and read `cv ax windows` again. The stack moved one cell left and one down, and the
  panel moved with it: the gap between the panel's right edge and the stack's left edge is what it was, and the
  panel is still on screen.
- **tour-replay.** Not driven. "Show the Tour" is in the menu bar icon's menu and the ribbon's ⋯ menu, and
  `cards-ax` can open neither. Report it as not verified. `tour-back` proves the same start at page 1, from
  the welcome, and not the two menu items.
- **settings-sections.** `cv ax key cmd+,`, then `cv ax section Updates`: in `cv ax tree` the sidebar's
  `AXRow [selected]` holds `AXCell "Updates"`, and the window has one `AXGroup`, named `Updates`, with
  `Check Now` and no `⌃⌥I`. `cv ax key cmd+w`: `cv ax windows` lists the stack alone. `cv ax key cmd+,`
  again: the group is `Shortcut` and the selected cell `Shortcut`.
- **settings-shortcut.** From any run, `cv ax key cmd+,` then `cv shot settings`: a 640 × 640 window
  on its Shortcut section, with the six sections in the sidebar (`AXTable "Settings sections"`), the
  title `Shortcut` and its lead, the shortcut row (`⌃⌥I`, Use Default dimmed) and the caption.
  `cv ax tree` names the recorder `"⌃⌥I" | "Shortcut"` with `value="Control-Option-I"`.
  `cv ax press "⌃⌥I"` starts recording (the button reads `Type shortcut…`). `cv ax key
  ctrl+cmd+h`: the button reads `⌃⌘H` and Use Default is enabled; a scratch run saves nothing, so a
  relaunch is back to `⌃⌥I`. Press the button again, by its new title (`cv ax press "⌃⌘H"`;
  `press "⌃⌥I"` now fails), and `cv ax key cmd+k`: a status line under the caption reads
  "⌘K can't be the shortcut. Use ⌃ or ⌘ with at least one other modifier key, so typing never
  triggers it." and the button is still recording. `cv ax key escape` cancels. `cv ax press "Use
  Default"` after a change restores `⌃⌥I`.
- **settings-updates.** Take the `shasum` of the owner's preferences as in `welcome-scratch`. Open
  Settings with `cv ax key cmd+,`, then `cv ax section Updates`. `cv ax tree` shows `AXCheckBox "Check
  for updates automatically"` and `AXButton "Check Now"`, both `[disabled]`, then the static text
  "Version 0.9 (1), a development build" and, under it, "Only builds made by scripts/package.sh check
  for updates." `cv shot settings-updates` is the proof image. After `cv stop` the `shasum` is
  unchanged.
- **settings-privacy.** `cv ax section Privacy`. `cv ax tree` of the Settings window has the
  headline "Two things leave your Mac. Nothing else does.", then the terms `Card text`, `Update
  checks`, `Your key` and `Nothing else`, each over its text. The first text begins "With a key saved,
  Ideator sends a card's text to Anthropic or OpenAI, whichever your key is for" (with a key saved it
  names that one company instead), and the last is "No analytics, no crash reports." The first is
  past `tree`'s 120 characters, so read its end in `cv shot settings-privacy`.

## Gotchas

- The welcome is not a stack: until a button, `cv ax windows` has one window and every stack recipe fails.
  `launch --welcome` waits for `Start the tour`, not `New`.
- While the tour runs, `cv ax windows` also lists the panel and the overlay, and `cv ax tree` lists the
  overlay as a window with no elements. Window counts and `w` indices therefore differ from a run with no
  tour. Recipes in other files count windows for runs without a tour, and a scratch run starts one only
  through `launch --welcome`.
- A title that shows a control's icon draws it as a chip. Match the words around it with `grep -F`, such as
  `to hide every card`. Whether `tree` reads the chip as the control's name or as U+FFFC is the first thing
  to note in a first run. U+FFFC would be a defect, since VoiceOver would read it too.
- A page that waits ignores an action taken before it asks. Press `New` on page 2, not on page 1. The desk
  changes, and the page does not advance.
- `cv ax click`, `focus`, `scroll` and `drag` activate Ideator, which page 5 reads as the cards coming
  forward. While a page's text is under test, use `press` and `type`, which do not activate it.
- Each Spread can write up to six `.md` files into the scratch folder, never the owner's. A click that deletes
  them moves each file it saved to the user's real Trash, as in [spread.md](spread.md). A click inside the 1 s
  save delay writes nothing.
- `press` does not hover. Page 4 shows the reader's card's hover buttons because the tour holds them open, and
  `tree` lists those buttons either way.
- A scratch run registers no global shortcut, but the tour still reads it as working, so page 3 names `⌃⌥I` as
  if it worked. Only a unit test reaches the wording for a shortcut that could not be claimed.
- Not verified by this harness: pressing the real global shortcut (page 3's other way to hide), a Space
  change, another app coming in front and the cards coming forward again (page 5's three title changes), the
  Documents prompt and the second prompt that Back on page 1 must not cause (the scratch folder is in
  `$TMPDIR`, which never asks), and the menu bar icon itself, whose ring on page 9 shows only as the overlay's
  PNG. The owner checks those by hand: `defaults delete com.systemlabs.Ideator TourSeen`, `defaults delete
  com.systemlabs.Ideator WelcomeSeen`, `tccutil reset SystemPolicyDocumentsFolder com.systemlabs.Ideator`,
  move `~/Documents/Ideator` aside, and open the installed app.
- The welcome with Continue alone, for an update, needs `TourSeen` saved and `WelcomeSeen` older than the
  build, which a scratch run cannot hold. `LaunchTests` pins it. A background start shows the same welcome;
  see `mcp-welcome` in [ai-tools.md](ai-tools.md).
- `welcome-scratch` compares the owner's real preferences, so another Ideator changing them between
  the two reads (Settings in the owner's own app) makes a false difference. Re-run it.
- A scratch run registers no global shortcut. Ending a recording without a pick (Esc, a click) registers
  nothing there. Picking a combination registers it in that process until `cv stop`, which can
  contend with the owner's Ideator, so pick an obscure one (`ctrl+cmd+h` is) and stop the run right
  after the recipe. `Use Default` after a pick registers `⌃⌥I`, the owner's own shortcut, in that
  process too, so end the recipe there and `cv stop` at once.
