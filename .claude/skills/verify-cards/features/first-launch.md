# First launch

The first time Ideator starts on a Mac it shows one card, "Welcome to Ideator", before it touches
the notes folder. The card says where the app is (no Dock icon, the menu bar icon, the notch), which
shortcut hides and shows the cards, that notes are Markdown files in `~/Documents/Ideator`, that
macOS asks for the Documents folder after Continue, that summaries are optional, that Ideator asks
GitHub once a day for updates, and that nothing else leaves the Mac. Continue, or Return, closes
the card and opens the stack. Settings has the shortcut recorder, the update controls and a line on
what leaves the Mac.

## Sub-features

- `welcome-card` The card shows its text and Continue, and no stack.
- `welcome-gate` The notes folder stays closed until Continue; Continue and Return both open it.
- `welcome-scratch` A scratch run shows no welcome on its own, and a forced one saves nothing.
- `settings-shortcut` The shortcut button records a new combination, refuses an illegal one by name,
  and goes back to the default.
- `settings-updates` The update controls are dimmed in a build that never checks, and the caption
  says why.
- `settings-privacy` The privacy line is the last row of Settings, under the Privacy heading.

## How to get to it (user POV)

- A fresh install: the card appears at launch. The owner can see it again with
  `defaults delete com.systemlabs.Ideator WelcomeSeen`, or by launching with `CARDS_SHOW_WELCOME=1`
  in the environment.
- Settings: **Settings…** in the menu bar icon's menu or the stack ribbon's ⋯ menu (not driven), or
  ⌘, while Ideator is active.

## Driving it with cards-verify

Preconditions:

- `cv build` ran after the last source change.
- `cv launch --welcome` for the card recipes (add `--seed` for `welcome-gate`). The welcome shows in a
  scratch run only because `--welcome` forces it, and Continue saves nothing there.
- Plain `cv launch` for the `settings-*` recipes is enough, and so is the welcome.

- **welcome-card.** Run `cv launch --welcome`. `cv ax tree` lists the text "Welcome to Ideator", the
  five paragraphs (the second names `⌃⌥I`, the fifth starts "Updates come from GitHub." and ends
  "Nothing else leaves your Mac.") and `AXButton "Continue"`, and no `New`.
  `cv ax windows` lists one window. `cv shot welcome` is the proof image.
- **welcome-gate.** Run `cv launch --welcome --seed`. Before Continue, `cv ax windows` lists one window
  and `cv ax tree` has no `New` and no count badge: the seeded cards have not been read. Run
  `cv ax press Continue`. The welcome window is gone, `cv ax tree` shows `New` and the badge `"2"`
  (Alpha and Beta, now loaded). Then `cv stop`, launch again the same way, and run `cv ax key return`
  instead of the press: the same result, which proves Return is Continue.
- **welcome-scratch.** Run `defaults export com.systemlabs.Ideator - 2>/dev/null | shasum` (empty output when the domain is absent, so the hash is stable). Run `cv launch
  --welcome`, `cv ax press Continue`, `cv stop`, then plain `cv launch` (it waits for `New`, so it
  fails if a welcome shows), then `cv stop`. Run the `shasum` again: equal.
- **settings-shortcut.** From any run, `cv ax key cmd+,` then `cv shot settings`: the shortcut row
  (`⌃⌥I`, Use Default dimmed), the caption, the Updates rows, the privacy line, and a window that
  fits its rows.
  `cv ax press "⌃⌥I"` starts recording (the button reads `Type shortcut…`). `cv ax key
  ctrl+cmd+h`: the button reads `⌃⌘H` and Use Default is enabled; a scratch run saves nothing, so a
  relaunch is back to `⌃⌥I`. Press the button again and `cv ax key cmd+k`: the caption reads
  "⌘K can't be the shortcut. Use ⌃ or ⌘ with at least one other modifier key, so typing never
  triggers it." and the button is still recording. `cv ax key escape` cancels. `cv ax press "Use
  Default"` after a change restores `⌃⌥I`.
- **settings-updates.** Take the `shasum` of the owner's preferences as in `welcome-scratch`. Open
  Settings with `cv ax key cmd+,`. `cv ax tree` shows `AXCheckBox "Check for updates automatically"`
  and `AXButton "Check Now"`, both `[disabled]`, and the static text "Version 0.9 (1), a development
  build. Only builds made by scripts/package.sh check for updates." `cv shot settings-updates` is
  the proof image. After `cv stop` the `shasum` is unchanged.
- **settings-privacy.** `cv ax tree` of the Settings window has, after the Privacy heading, the
  static text beginning "With a key saved, Ideator sends a card's text to Anthropic" and ending
  "Nothing else leaves your Mac: no analytics, no crash reports."

## Gotchas

- The welcome card is not a stack: `cv ax windows` has one window and every stack recipe fails until
  Continue. `launch --welcome` waits for `Continue`, not `New`.
- Not verified by this harness: pressing the real global shortcut (the key events go to the pid,
  never through the system's hotkey path, and a scratch run does not register it), and the Documents
  prompt (the scratch folder is in `$TMPDIR`, which never asks). The owner checks those by hand:
  `defaults delete com.systemlabs.Ideator WelcomeSeen`, `tccutil reset SystemPolicyDocumentsFolder
  com.systemlabs.Ideator`, move `~/Documents/Ideator` aside, and open the installed app.
- `welcome-scratch` compares the owner's real preferences, so another Ideator changing them between
  the two reads (Settings in the owner's own app) makes a false difference. Re-run it.
- A scratch run registers no global shortcut. Ending a recording without a pick (Esc, a click) registers
  nothing there. Picking a combination registers it in that process until `cv stop`, which can
  contend with the owner's Ideator, so pick an obscure one (`ctrl+cmd+h` is) and stop the run right
  after the recipe.
