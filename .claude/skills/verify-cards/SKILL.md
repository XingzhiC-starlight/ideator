---
name: verify-cards
description: Drive the real Ideator macOS app (menu bar app, card windows, the stack) the way a user does, from the shell, and capture proof (screenshots, accessibility trees, the Markdown files and sidecar it writes). Use after any change to Cards/*.swift that a user could see or that changes what is saved, before saying the change works, or to reproduce a UI bug.
---

# Verify Ideator

Ideator is a native AppKit menu bar app: each card is a borderless window, the stack is one more
window with a tan ribbon (New, Clarity, Hide all, ⋯), and every card is a Markdown file in a
folder plus a hidden sidecar `.cards.json`. This skill starts an isolated copy of the app on an
empty temp folder and drives it through macOS Accessibility, by pid, so it never touches the
owner's own Ideator or `~/Documents/Ideator`.

Everything goes through one script. From the repo root:

```bash
.claude/skills/verify-cards/scripts/cards-verify
```

prints its usage. The examples below write `cv` as shorthand for that path. In every command, type
the path itself from the repo root. The Bash tool keeps no shell function between calls, and
worktree isolation refuses a function or a variable as the command name.

Unit tests are not this skill's job. Run them with the
[run-ideator-tests](../run-ideator-tests/SKILL.md) skill.

## Launch

```bash
cv build              # xcodebuild into build/VerifyDerivedData, and compile the cards-ax helper
cv launch --seed      # or plain `cv launch` for an empty folder
cv launch --welcome   # the first-launch card, as a stranger sees it
```

- `build` uses its own derived data (`build/VerifyDerivedData`), never `build/DerivedData` or
  Xcode's, so it does not collide with a build another session or Xcode is running. Rebuild after
  every source change; `doctor` flags a stale binary.
- `launch` makes a fresh run: a card folder under `$TMPDIR/cards-verify/<run>/folder` and an
  evidence folder `build/verify-evidence/<run>/`. It starts the app with `open -n … --args
  -CardsFolder <folder>` and waits until the stack window answers over Accessibility with its
  New button. That is ready. It prints the evidence path.
- `--seed` writes two cards before launch: `seed-a.md` ("Alpha card", one body line) and
  `seed-b.md` ("Beta card", two body lines). With no sidecar both start in the stack, Alpha on
  top. Without `--seed` the stack starts on its blank page with a count of 0.
- `--seed SIDECAR` also copies SIDECAR in as `.cards.json` before launch, to start from saved
  places, Clarity or summaries.
- `--welcome` forces the first-launch card even though a scratch run never shows it: it adds
  `--env CARDS_SHOW_WELCOME=1` to `open`, and the command line stays `… --args -CardsFolder <folder>`.
  Ready is then the card's Continue button, not New. It combines with `--seed`, which goes second.
  Continue writes nothing of the owner's (a scratch run has no saved preferences).
- One run at a time: `launch` refuses while the current run's app is still up.
- The app activates itself at launch and on most clicks, so it takes focus from whatever the user
  is doing.

## Doctor

```bash
cv doctor
```

Read-only. Checks that the pid is this run's binary on this run's folder, that no Swift source is
newer than the binary, that the folder exists, and that the stack window (or, after `launch
--welcome` and before Continue, the welcome card) answers. It lists other
Ideator processes, such as the owner's Xcode run, as a note. Never drive those. Run `doctor` first
whenever a step fails or anything looks off. It must print `healthy` before any proof counts.

## Drive

`cv ax COMMAND …` runs the `cards-ax` helper against this run's pid
([source](scripts/cards-ax.swift), header lists every command):

| Command | What it does |
| --- | --- |
| `cv ax tree` | Every window and element: role, name, value, `[disabled]`, `[focused]`, frame |
| `cv ax press NAME [WINDOW]` | Accessibility press on the first button whose title, description or tooltip is NAME |
| `cv ax text [WINDOW]` | The text of each text area, one JSON string per line |
| `cv ax focus WINDOW` | A real click into that card's text (activates Ideator) |
| `cv ax type 'TEXT'` | Key events to the app; `\n` is Return |
| `cv ax key COMBO` | One key: `cmd+b`, `cmd+z`, `cmd+q`, `tab`, `shift+tab`, `return`, `delete`, arrows (`shift+down`, `cmd+left`)…; a `cmd+` combo activates Ideator first, since menu shortcuts need it |
| `cv ax click WINDOW FX FY` | A real mouse click at a fraction of the window (0..1 from top-left) |
| `cv ax scroll WINDOW DX DY` | One scroll-wheel event over the window |
| `cv ax drag WINDOW FX FY DX DY` | Press at a fraction of the window, drag by DX,DY points, release |
| `cv ax windows` | Window ids and frames, for `screencapture -l` |
| `cv ax act LABEL ACTION [WINDOW]` | Run an accessibility action (`AXPress`, or a custom one such as `Move up`) on the first element whose title, description or help starts with LABEL |
| `cv ax where LABEL` | Screen `x y` of the center of the first element whose name starts with LABEL |
| `cv ax mouse down\|drag\|up\|move X Y` | One raw mouse event at a screen point, for a drag you want to stop partway |
| `cv ax dragat X Y DX DY` | Press at a screen point, drag by DX,DY, release |
| `cv ax listen SECONDS` | Print each VoiceOver announcement the app posts, for that long. Open the popover first |

WINDOW is `stack`, `card=<first line of the card>`, or an index from `tree` (`w0`). Indices follow
the z-order and change after any click, so use the names.

Stable handles in this app, all from the code:

- Stack ribbon buttons: `New`, `Clarity`, `Hide all` / `Show all`, `Settings and quit` (the ⋯
  menu). Clarity always has that name. Its state is the `value="off"` or `value="on"` that `tree`
  prints on its line (its tooltip, `Clarity is off: click to collapse every card` or `Clarity is
  on: click to expand every card`, says it too), and its text color, which only `shot` shows.
- Card buttons (popped card, or the stack's selected card): `Collapse this card` / `Expand this
  card`, `Refresh summary` (collapsed, with two or more body lines), `↩ Stack` (popped only), `↗ Pop`
  (stacked card only; `[disabled]` with the tooltip `Desktop full` while the desktop is full),
  `Delete this card`. They fade in on hover, but they are in the tree at alpha 0 too, so `press`
  works without hovering. The stack's blank page has none of them.
- `press` matches a button's whole title, description or tooltip, so `press "↗ Pop"` and `press
  Clarity` work, and `press Pop` does not.
- Delete confirmation: a sheet "Delete this card?" with buttons `Delete` and `Cancel`.
- Count badge: a button. `tree` prints it as `AXButton "2" | "2 cards in the stack" | "Arrange the stack"`
  (title = number of stacked cards, then its VoiceOver label, then its tooltip), `[disabled]` at
  zero. `press "Arrange the stack"` opens the arranger; at zero it fails with `is disabled`.
- Arranger: an `AXPopover` under the stack window holding `AXTable "Stack order"`. Each row is an
  `AXRow` (`[selected]` is the keyboard's row) holding one `AXCell` named `<title>, 3 of 7`, plus
  `, current card` for the shown one, with `actions=[Move up, Move down, …]` (AppKit lists them
  twice; they are one pair). `act "Beta card" "Move up"` is VoiceOver's Move up on that row, and
  `act "Beta card" AXPress` is its press. ⌥↑ and ⌥↓ are `cv ax key opt+up` and `opt+down`; the keys go
  to the popover, which is the key window while it is open. The grip is the right 30 points of a row:
  its center is `where "<title>"` plus 118 on x.
- "Desktop full": static text `Desktop full` in the ribbon, only while it applies.
- Edge bands: the outer 5% of the stack window. `cv ax click stack 0.985 0.6` = next,
  `cv ax click stack 0.015 0.6` = previous.
- Swipe: `cv ax scroll stack -40 0` = next, `cv ax scroll stack 40 0` = previous (a wheel event
  with no phase flips once).
- Typing: `press New` leaves the caret on the new card's header line, so `type` goes there. To
  edit another card, `focus` it first.

The first line of a card's text is its title, saved as `# <title>`. Saves are debounced by one
second, and also happen when Ideator resigns active. Wait 1.5 s before reading files.

The feature map in [`features/`](features/README.md) has the recipe for each user-facing feature.
Start from its README.

## Clipboard

Copy and paste checks use the owner's clipboard, so save it first and restore it after:

```bash
cv clip save                       # every type on the clipboard, kept until restore
cv clip set 'TEXT' ['<ul>…</ul>']  # what a paste will read: plain text, and HTML as public.html
cv ax key cmd+v
cv ax key cmd+c && cv clip show    # what a copy wrote: the types, the text and the HTML
cv clip restore                    # put the owner's clipboard back
```

`clip set` refuses until `clip save` ran, and `cv stop` restores a saved clipboard if you forget.
Never print the owner's clipboard; compare `osascript -e 'clipboard info' | shasum` and
`pbpaste | shasum` before and after to prove the restore.

## Evidence

```bash
cv shot after-new       # every on-screen window as PNG + the accessibility tree
cv files after-new      # copy *.md and .cards.json, and print them
cv note "popped Alpha; badge 1 -> 0"
```

Everything lands in `build/verify-evidence/<run>/` (`log.txt` has a timestamped line per step,
`app.log` the app's stdout/stderr). That folder survives `stop`. Proof standards:

- Drive the real user path: ribbon and card buttons, typing, clicks, scrolls, drags. Never edit
  the sidecar or call into the app's code to set up state the UI could reach.
- Capture the action and the resulting state: a `shot` or `tree` before and after, not only the
  last screen.
- Check side effects as well as what shows. Every change that should persist needs `cv files`
  showing the `.md` text and the sidecar (`placements`, `stack`, `collapsed`, `clarity`). Popping
  or returning a card changes only the sidecar; typing changes the `.md`.
- Read the UI through `cv ax tree` / `cv ax text`, then look at the PNG to confirm the look
  (header bold, summary lighter, ribbon only).

## Cleanup

```bash
cv stop
```

Kills only the pid this run started (it checks the command line first), deletes the run's temp
card folder, and keeps `build/verify-evidence/<run>/`. Never `pkill Ideator` or kill by name: the
owner's Xcode run is also called Cards. Run `stop` after every failed attempt too, before the next
`launch`.

## Gotchas

- Deleting a card through the app moves its `.md` to the user's real Trash (that is the feature).
  Those files are named by timestamp and are harmless. Leave them, and say so in the report.
- A scratch run (`cv launch` passes `-CardsFolder`) never reads or writes the login Keychain, so
  it starts with no key, whatever the owner has saved, and no macOS Keychain prompt can block the
  UI. Collapsed cards with two or more body lines show "Summary unavailable" unless you paste a
  key into Settings, which then lasts for that run only (Settings says "held for this run only").
  Pasting a real key makes the run call the real API, so prefer one-line bodies when proving
  collapse (they show the line itself and never call the API).
- A scratch run (`cv launch` passes `-CardsFolder`) does not register the global shortcut (⌃⌥I by
  default) and never reads or writes the owner's saved shortcut, so it cannot take the shortcut from
  the owner's Ideator. The harness also cannot press it. Prove Hide all with the ribbon button, not
  the hotkey.
- The menu bar icon is not driven by this skill. The ribbon's ⋯ menu has the same Settings… and
  Quit. Check for Updates… is only in the menu bar icon's menu; Settings' Check Now does the same.
- A scratch run never starts Sparkle, and neither does any build `cv build` makes, which
  `scripts/package.sh` did not stamp. No Sparkle object exists, so nothing goes to GitHub and no
  `SU*` key reaches the owner's `com.systemlabs.Ideator` preferences. Settings' update controls
  are dimmed, and the caption under them says why.
  Updating is proved by `scripts/verify-update.sh`, not by `cv`; see
  [features/updates.md](features/updates.md).
- `click`, `focus`, `scroll` and `drag` move the real pointer and click the topmost window at that
  point. The helper brings Ideator forward first, but a window the user drags on top in between
  would take the click. `press`, `type`, `key` and `tree` don't depend on the pointer.
- The pointer, keyboard focus and screen are shared with the owner and with every other agent's
  app or test host. A one-off input anomaly (a stray character, an odd selection, buttons left
  showing, a test-host crash) stays INCONCLUSIVE until it repeats, or goes away, in a run with
  nothing else driving the Mac. Do not blame it on someone's input without that run.
- Accessibility builds the app's tree lazily; the helper retries the first read for up to 3 s.
- The Accessibility and Screen Recording permissions belong to the app that runs the shell. If
  `cards-ax` says it has no Accessibility permission, or screenshots come out as wallpaper only,
  the user has to grant it in System Settings › Privacy & Security.
