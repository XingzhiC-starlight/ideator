# Ideator Settings: design guideline

Status: approved, 2026-10-30, and ready to build. The content and section order are the agreed plan
(2026-10-29). The visual rules come from the research-journal brand brief. The new wording and the
three behavior changes were approved on 2026-10-30 (§1, Decisions). Quoted copy is final: build it
word for word.

**Intent:** Settings reads like a page from a research journal printed on warm stone: ivory paper,
slate ink and a slate sidebar, flat hard-edged controls, one clay accent kept for a single job, and
emphasis made with type and underlines, never with color or glow.

---

## 1. Context and goals

**What this covers.** The Settings window only (`Cards/Settings.swift`). Cards, the stack and the
welcome card keep their warm-paper palette (DESIGN.md › Color and glass).

**Goals**

- Each of the six sections is one page, reached from a flat sidebar, so no section is buried in a
  long scroll.
- Every control states its current state in words or a glyph, not only in color.
- WCAG 2.2 AA, keyboard-first, with a visible focus ring on every focusable control.
- Every rule maps to a token, so a build can be reviewed against this file line by line.

**Non-goals**

- No new settings. Launch at login, Show folder and About are separate proposals.
- No Dark Mode variant. The window always uses the light look, as cards already do. The slate
  sidebar and the slate Privacy card already supply the dark half of the ivory ↔ slate rhythm.
- No change to what any setting does. Only layout, drawing, the approved copy and the three
  behavior changes below change.

**Decisions (2026-10-30)**

- All new wording in §3.13 is approved as written. Each section opens with a summary line under its
  title, and Shortcut's and Spread's old captions are split between that line and the caption.
- Three behavior changes are in: a status line when the Keychain refuses the key (§3.13, AI
  Summary), Save disabled while the key field is empty (§3.4), and Remove Key disabled while no key
  is saved (§3.12).
- The code font is SF Mono, not JetBrains Mono (§2.2).
- The Privacy card opens with "Two things leave your Mac. Nothing else does.", and its update line
  now says the daily check runs only while automatic checks are on.

**Where the brief and the rules disagree.** Accessibility and macOS conventions won in each case:

| Brief says | This guideline does | Why |
| --- | --- | --- |
| Primary font: "use the existing one" | SF Pro, the system font the app already uses | It's already in the app. It also settles the Anthropic Sans license question, because no font needs licensing. |
| Display serif: "use the existing one" | New York, the macOS system serif (`.withDesign(.serif)`) | The app has no serif. New York ships with macOS and needs no license. |
| Mono: JetBrains Mono | SF Mono (`NSFont.monospacedSystemFont`) | Chosen 2026-10-30. It's macOS's own code font and matches SF Pro, and it's used in two places only (§2.2). JetBrains Mono would add a font file and a license for two strings. |
| `text` = #111827 | Not used. All text is `ink` #141413. | #111827 is a cool blue-black, a second near-black that clashes with the warm slate. Contrast is the same (17.5:1 vs 16.9:1). |
| `surface` = #FFFFFF, but "never pure white" | White only inside input wells (key field, shortcut recorder, instruction editor) | White marks the places you can type. No page, card or button is white. |
| `success` #16A34A, `warning` #D97706 | Darker `*Strong` variants (§2.1) | The brief's values are 3.1:1 and 3.0:1 on ivory, which fails 4.5:1 for text and only just reaches 3:1 for a glyph. |
| `danger` #DC2626 | `dangerStrong` #B91C1C | #DC2626 is 4.6:1, too close to the limit. #B91C1C is 6.2:1. |
| Weights 100–900 | 400, 500 and 600 only | Weights under 400 fail legibility at 12–14 pt, and nothing in Settings needs above 600. |
| Buttons have 0 px corners | Checkboxes have square corners too. The Top / Bottom radios become a two-part segmented control. | A round radio would be a second curve. A segmented control still shows "pick one" without one. |

---

## 2. Design tokens and foundations

Tokens live in code as named constants (§2.7). A view never writes a raw value, matching
DESIGN.md's rule "a view never writes a color literal".

### 2.1 Color

Brand values (raw): `slate` #141413 · `ivory` #FAF9F6 · `white` #FFFFFF · `clay` #C15F3C.

Semantic tokens (use only these):

| Token | Value | Use | Contrast (measured) |
| --- | --- | --- | --- |
| `canvas` | ivory #FAF9F6 | pane background, default button fill | n/a |
| `inverse` | slate #141413 | sidebar, Privacy card, Save's fill, selected segment, ticked checkbox | n/a |
| `surface` | white #FFFFFF | inside input wells only | n/a |
| `ink` | slate #141413 | all text on `canvas` and `surface`; borders of buttons and checkboxes; focus ring on light | 17.5:1 on canvas, 18.4:1 on surface |
| `inkInverse` | ivory #FAF9F6 | text on `inverse`; focus ring on dark | 17.5:1 on inverse |
| `inkMuted` | #5E5D59 | captions, placeholders, the version line | 6.3:1 on canvas, 6.6:1 on surface |
| `inkInverseMuted` | #A3A198 | sidebar rows that aren't selected | 7.1:1 on inverse |
| `border` | #858379 | input wells, unticked Spread cells | 3.6:1 on canvas, 3.8:1 on surface (≥ 3:1, WCAG 1.4.11) |
| `inkDisabled` | #ABA9A1 | disabled labels and borders | 2.2:1, allowed because WCAG 1.4.3 exempts disabled controls |
| `wash` | slate at 6 % over canvas (renders #ECEBE8) | hover fill | ink on wash 15.5:1 |
| `inverseRaised` | #3D3D3A | Save while pressed | inkInverse on it 10.4:1 |
| `accent` | clay #C15F3C | **only** the fill of a ticked Spread cell | 4.0:1 against canvas; its ivory check 4.0:1 (≥ 3:1 for graphics) |
| `successStrong` | #15803D | success glyph | 4.8:1 on canvas |
| `warningStrong` | #B45309 | warning glyph | 4.8:1 on canvas |
| `dangerStrong` | #B91C1C | error glyph, error border | 6.2:1 on canvas |

Rules:

- The clay `accent` **must** appear in exactly one place: ticked Spread cells. A second use needs a
  change to this file first. (Clay over cobalt was chosen on 2026-10-29.)
- Status hues **must** color only a glyph or a 2 pt error border. Status text is always `ink`.
- **Increase Contrast** (System Settings › Accessibility › Display) **must** switch `border` and
  `inkMuted` to `ink`, and `inkInverseMuted` to `inkInverse`. Read
  `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` and redraw on
  `accessibilityDisplayOptionsDidChangeNotification`.

### 2.2 Typography

| Role | Font | Size / line | Weight | Use |
| --- | --- | --- | --- | --- |
| `title` | SF Pro | 24 / 32 | 600 | the pane title (the section's name) |
| `display` | New York | 24 / 32 | 400 | the Privacy card's headline, and nothing else |
| `lead` | SF Pro | 16 / 24 | 400 | the one-line summary under each title |
| `label` | SF Pro | 14 / 20 | 500 | group labels, buttons, sidebar rows, field labels |
| `body` | SF Pro | 14 / 20 | 400 | checkbox and radio text, editor text, Privacy card text |
| `caption` | SF Pro | 12 / 16 | 400 | captions and status lines |
| `mono` | SF Mono | 12 / 16 (version line), 14 / 20 (key field) | 400 | the version line and the API key field |

- Sizes **must** come from 12 / 14 / 16 / 20 / 24 / 32. Settings uses 20 nowhere and keeps 32 in
  reserve, since a 408 pt column has no room for it.
- Don't set tracking by hand. SF Pro's optical sizes already tighten it at 20 pt and up.
- The serif **must** appear only on an `inverse` card. Pane titles and the sidebar stay SF Pro.
- Emphasis inside text uses weight 600 or a 1 pt underline. Never color, italics or all caps.

### 2.3 Spacing

| Token | Value | Use |
| --- | --- | --- |
| `s1` | 4 | label → its caption |
| `s2` | 8 | title → lead; control → its caption; between controls in a row; checkbox → its label |
| `s3` | 12 | between rows within a group; between Privacy card items |
| `s4` | 16 | sidebar row inset; Privacy card headline → list |
| `s5` | 24 | lead → first group; between groups; Privacy card padding |
| `s6` | 32 | pane side and bottom padding |

Spacing **must** come from this scale. Today's 10 and 18 pt gaps go away (§6.2).

### 2.4 Shape, borders, elevation

- Corner radius: 0 everywhere. The single exception is Save (§3.4): top corners 0, bottom corners
  `ctaRadius` = 8.
- Borders: 1 pt. Focus and error borders: 2 pt.
- Shadows: none. No `NSShadow`, no layer shadow, no vibrancy, no blur. Surfaces are separated by the
  ivory ↔ slate edge alone.
- Motion: none. The only timed change is "Copied" reverting after 2 s, which swaps a label and
  doesn't animate.

### 2.5 Layout

```
┌──────────────┬─────────────────────────────────────────────┐
│ ● ● ●        │                                             │  ← transparent title bar, 28
│              │  Shortcut                       title 24/600│
│ ▌Shortcut    │  Hides or shows every card…       lead 16   │
│  Spread      │                                             │
│  AI Summary  │  [ ⌃⌥I        ] [Use Default]               │
│  MCP         │  Click the shortcut, then press…  caption   │
│  Updates     │                                             │
│  Privacy     │                                             │
│   168        │  ←32→  content column 408           ←32→    │
└──────────────┴─────────────────────────────────────────────┘
                         640 × 640 content
```

- The window is 640 × 640 pt of content, fixed, not resizable, `.titled` + `.closable`, with
  `fullSizeContentView` and a transparent title bar. Its title stays "Ideator Settings", hidden
  but still read by VoiceOver and the Window menu.
- Sidebar: 168 wide, full height, filled with `inverse`. The first row's top is at 52, which is the
  28 pt title bar plus `s5`.
- Pane: filled with `canvas`. Content starts at y 52, with 32 at the sides and bottom. The content
  column is 408 wide.
- The tallest pane (MCP) is estimated at about 610 pt with today's copy, so 640 fits it without
  scrolling. Measure it in the build. A pane taller than the window scrolls vertically inside the
  pane. The sidebar never scrolls.
- On a screen with less room than the window needs, the window shrinks to fit and the pane
  scrolls. This keeps today's rule.
- The window always opens on Shortcut. While it stays open, the chosen section stays selected.

### 2.6 Appearance

- Set `window.appearance = NSAppearance(named: .aqua)`, so Dark Mode leaves the window unchanged.
- Reduce Transparency and Reduce Motion: nothing to do, since the window uses neither.

### 2.7 Where tokens live in code

- Colors go in `Palette.Settings` (Palette.swift), under the token names above.
- Spacing, sizes and fonts go in one `SettingsStyle` enum: `s1`…`s6`, `sidebarWidth`,
  `contentWidth`, `controlHeight` = 28, `ctaRadius` = 8, `focusWidth` = 2, `focusOffset` = 2, and
  the type roles.
- Add a "Settings palette" table to DESIGN.md › Color and glass, with the contrast column.

---

## 3. Component rules

All controls stay AppKit controls (`NSButton`, `NSTextField`, `NSTextView`, `NSTableView`), drawn
by custom cells. That keeps roles, values, keyboard handling and VoiceOver for free. Don't replace a
control with a plain `NSView` that draws itself.

### 3.1 State matrix

Every row lists the states the control has. "Ring" is the focus ring defined in §3.2.

| Control | Default | Hover | Focus-visible | Active / pressed | Disabled | Loading | Error |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Button | `canvas` fill, 1 pt `ink` border, `label` in `ink`, height 28, padding 12 | fill `wash` | ring | fill `inverse`, label `inkInverse` | border and label `inkDisabled`; no hover; skipped by Tab | — | — |
| Save (primary) | fill `inverse`, label 14/600 `inkInverse`, shape 0/0/8/8 | label gets a 1 pt underline | ring follows the shape | fill `inverseRaised` | no fill, 1 pt `inkDisabled` border, `inkDisabled` label, same shape | — | — |
| Key field | `surface` well, 1 pt `border`, `mono` 14 | I-beam cursor only | border becomes 2 pt `ink`, drawn inside so the layout doesn't move | — | — | — | border 2 pt `dangerStrong` plus a danger status line |
| Shortcut recorder | `surface` well, 1 pt `border`, `label` in `ink`, min width 120 | fill `wash` | ring | **recording:** fill `inverse`, label `inkInverse` "Type shortcut…" | never disabled | — | a refused combination stays recording, with a danger status line |
| Checkbox | 16 × 16 box, 1 pt `ink` border, `canvas` fill; ticked: `inverse` fill with an 11 pt `inkInverse` check | box border 2 pt | ring around the box and the label | unticked box fills with `wash` | box and label `inkDisabled` | — | — |
| Segmented (Top / Bottom) | two 28-tall segments, at least 72 wide, 1 pt `ink` border with a shared middle line; selected: `inverse` fill, label 600 `inkInverse`; the other: `canvas`, 400 `ink` | unselected segment fills with `wash` | ring around the selected segment | `wash`, then selects on release | borders and labels `inkDisabled`; selected fill `inkDisabled` with a `canvas` label | — | — |
| Spread cell | 32 × 24, `canvas` fill, 1 pt `border`; ticked: `accent` fill with an 11/600 `inkInverse` check | 2 pt `ink` border | ring with offset 1 | — | the stack's cell: `canvas`, 1 pt `inkDisabled` border, `rectangle.stack` glyph in `inkMuted`, not focusable | — | — |
| Instruction editor | `surface` well, 1 pt `border`, `body` in `ink`, 8 inset, 408 × 112 | — | border 2 pt `ink` | — | — | — | refused edit: border 2 pt `dangerStrong` until the next accepted edit, and the caption swaps to the refusal with a danger glyph |
| Connect button | Button, with a `doc.on.doc` glyph before the label | as Button | ring | as Button | while Ideator runs from a temporary place, with a warning status line | **Copied** for 2 s: label "Copied", `checkmark` glyph, width fixed to the wider of the two labels | — |
| Check Now | Button | as Button | ring | as Button | while the updater can't check (welcome card up, a download running, a build that never checks) | Sparkle shows its own progress window, and the button stays disabled until it ends | — |
| Sidebar row | `label` in `inkInverseMuted` on `inverse`, 32 tall, inset 16 | label `inkInverse` plus a 1 pt underline | (selected row) 2 pt `ink` ring, inset 4 inside the row | — | — | — | — |
| Sidebar row, selected | `canvas` fill running to the sidebar's right edge, so it joins the pane; label 14/600 `ink` | — | as above | — | — | — | — |

Cursor: always the arrow. macOS controls don't show a pointing hand.

### 3.2 Focus ring

- A 2 pt solid line, square corners, 2 pt outside the control (offset 1 for Spread cells, whose
  gaps are 4).
- Its color is `ink` on `canvas` and `inkInverse` on `inverse`. That's ≥ 17:1 against what it
  touches, and the 2 pt gap keeps it apart from the slate Save button.
- Draw it yourself: set `focusRingType = .none` and draw the ring while the control is first
  responder in the key window. Redraw on `becomeFirstResponder` and `resignFirstResponder`.
  - Trade-off: the system accent color no longer tints the ring. That's accepted, because a blue
    glow breaks the brand, and a 2 pt slate line is easier to see on ivory.
  - Don't: set `.none` without drawing a replacement.

### 3.3 Button (secondary)

- Anatomy: the label, plus an optional leading 14 pt SF Symbol with an 8 pt gap.
- The button sizes to its label and never truncates it. Labels have at most 3 words (§5).
- In a row, buttons sit 8 apart. A row that ends in a commit button is right-aligned to the column.

### 3.4 Save (the primary button)

- **Must** be the only primary button in Settings. Save is the only action that doesn't apply at
  once. Everything else takes effect on click.
- Shape: draw an `NSBezierPath` with square top corners and 8 pt rounded bottom corners.
- Placement: trailing, after Remove Key, and the row is right-aligned to the key field's trailing
  edge.
- `keyEquivalent = "\r"`, so Return in the key field saves.
- **Must** be disabled while the field is empty (decided 2026-10-30). Today it's enabled and does
  nothing.

### 3.5 Key field

- `NSSecureTextField` in `mono` 14, 408 wide, 28 tall, with 8 horizontal padding. Placeholder
  "sk-ant-… or sk-…" in `inkMuted`.
- Paste **must** work (WCAG 3.3.8). Never block paste or autofill.

### 3.6 Shortcut recorder

- Keeps today's behavior: Esc, a click or leaving the window cancels, and the live shortcut is
  released while recording.
- When recording starts, VoiceOver announces "Recording. Press the new keys, or Escape to
  cancel."
- Accessibility label "Shortcut". Value: the shortcut spelled out, for example "Control-Option-I".

### 3.7 Segmented control (Top / Bottom)

- Keep two `NSButton` radios in one superview with one action. AppKit treats them as one group,
  VoiceOver still says "radio button, 1 of 2", and tests can still find them by title.
- Draw them as joined segments with a custom cell.
- The label "Cards from AI tools go to:" sits 8 before the control, on the same row.

### 3.8 Spread cell picker

- A 5 × 4 grid of 32 × 24 cells with 4 pt gaps (176 × 108 in all). Each cell clears WCAG 2.5.8's
  24 × 24 target.
- **One** tab stop. ← ↑ → ↓ move focus between cells, skipping the stack's cell, and Space
  toggles the focused cell.
  - Hint: the picker is the key view, it tracks `focusedCell`, and it draws the ring on that cell.
  - Don't: 20 tab stops, as today.
- VoiceOver keeps "Spread cell 1" … "Spread cell 20" (the spec fixes these names), with role
  checkbox and value ticked or not ticked. The stack's cell reads "The stack, dimmed".

### 3.9 Instruction editor

- 408 × 112, scrolls inside itself, plain text only, with smart quotes, dashes and replacements
  off (today's settings).
- Reset to Default sits below it, left-aligned, and is disabled while the text is the standard
  one. Reset is undoable (today's behavior).

### 3.10 Status line

- Anatomy: an optional 12 pt glyph in its status color, 4 pt gap, then text in `caption` `ink`,
  wrapping within 408.

| Status | Glyph | VoiceOver prefix | Used for |
| --- | --- | --- | --- |
| neutral | none | none | no key saved; no Spread cell ticked; updates off in this build |
| success | `checkmark.circle` (`successStrong`) | "Done:" | a key is saved; setup copied |
| warning | `exclamationmark.triangle` (`warningStrong`) | "Warning:" | macOS has a shortcut on the same keys; Ideator runs from a temporary place |
| error | `xmark.octagon` (`dangerStrong`) | "Error:" | shortcut not registered; refused combination; Keychain refused; instruction over the limit |

- The prefix is the glyph's `accessibilityDescription`, so it's read and never shown.
- Every change of a status line **must** post an announcement (`NSAccessibility.post(element:
  notification: .announcementRequested, userInfo:)`) through an injected `announce: (String) ->
  Void`, so tests can read what was said.
- A status line appears only while it has something to say. The caption above it, which explains
  the control, stays put.

### 3.11 Privacy card (the feature card)

- An `inverse` block, full column width, padding 24, square corners.
- Headline in `display` (New York 24) `inkInverse`. Then a list with 16 between headline and list.
  Each item is a term (14/600) on its own line, then text (14/400), with 12 between items.
- The only serif in the window, and the only dark block inside a pane.

### 3.12 Edge cases

- **Long labels:** buttons grow and never truncate. If the Connect row grows past 408, it wraps
  to a second line rather than shrinking buttons. Sidebar names must fit in 136 pt; rename a section
  instead of wrapping it.
- **Overflow:** captions and status lines wrap and never get "…". The editor scrolls inside
  itself, and a pane taller than the window scrolls.
- **Empty states:** no key (neutral status; Remove Key **must** be disabled); no Spread cell
  ticked (neutral status, today's text); AI tools off (Top / Bottom disabled, editor still
  editable); a build that never checks for updates (both controls disabled, caption says why).
- **Pointer and touch:** Ideator is a Mac app, so a trackpad tap is a click. Every target is at
  least 24 × 24, and a checkbox's label is part of its target. Nothing needs a drag.
- **Language:** English only. If localization comes, recheck widths in §3.12 and the sidebar
  limit.

### 3.13 The six panes

Each pane is: `title`, then `lead` (8 below), then groups 24 apart.

**1 · Shortcut** (opens first)
- Lead: "Hides or shows every card, from any app."
- Row: the recorder, then Use Default (disabled while ⌃⌥I is in use).
- Caption: "Click the shortcut, then press the new keys."
- Status, when needed: the macOS clash (warning), not registered (error) or a refused combination
  (error), all in today's words.

**2 · Spread**
- Lead: "Spread, on the stack's ribbon, puts a new card in each ticked cell."
- The picker.
- Caption: "Its next click gathers them into the stack, and the one after puts them back.
  Option-click starts a new set. The dimmed cell is the stack's."
- Status, when no cell is ticked (neutral): "No cell is ticked, so Spread makes no card. Tick the
  cells it should fill."

**3 · AI Summary**
- Lead: "A collapsed card shows a summary that Anthropic or OpenAI writes, using your own
  key."
- Label "API key", the key field, the status line, then the row Remove Key, Save.
- Status: today's key status (success when a key is saved, neutral when none). If the Keychain
  refuses: "The Keychain refused the change." followed by today's key status (error). The beep
  stays. This changes CARDS-SPEC.md › Settings, which today says only that it beeps.

**4 · MCP**
- Lead: "Let AI tools like Claude Code add cards to Ideator. They connect through MCP, a
  standard way for AI tools to reach apps."
- Group: label "Connect an AI tool", then the row Claude Code, Codex, Claude Desktop,
  then today's caption, or the "Copied for …" text, or the move-first warning.
- Group: the checkbox "Let AI tools add cards", then the row "Cards from AI tools go to:" Top |
  Bottom.
- Group: label "Instruction for AI tools", today's caption, the editor, Reset to Default.

**5 · Updates**
- Lead: "Ideator gets new versions from GitHub."
- Row: the checkbox "Check for updates automatically" on the left, Check Now on the right.
- Caption: the version line in `mono`, selectable so it can be copied into a bug report. Then today's
  sentence about whether this run checks.

**6 · Privacy**
- The Privacy card, whose company names follow the saved key (as today):
  - Headline: "Two things leave your Mac. Nothing else does."
  - **Card text**: "With a key saved, Ideator sends a card's text to ‹who›, using your own key, to
    write its summary. It does so whenever a card has no summary for its text as it is now: after
    you change a card, when you save a key, at launch after a failed try, and after an update that
    changes how Ideator asks for summaries."
  - **Update checks**: "Once a day while automatic checks are on, and whenever you click Check
    Now, Ideator asks GitHub whether a newer version exists. GitHub sees your IP address and which
    version you have." ("while automatic checks are on" is new. Today's line doesn't say that
    unticking the box stops the daily check.)
  - **Your key**: "The key stays in your login Keychain."
  - **Nothing else**: "No analytics, no crash reports."
- ‹who› is "Anthropic", "OpenAI", or "Anthropic or OpenAI, whichever your key is for" while no key
  is saved.

---

## 4. Accessibility acceptance criteria

Each criterion can be checked in a unit test (U) or in a manual pass with VoiceOver and the keyboard
(M).

| # | Criterion | WCAG | How to test |
| --- | --- | --- | --- |
| A1 | Every text token pair in §2.1 is ≥ 4.5:1, and `border`, `accent` and the status glyphs are ≥ 3:1 on `canvas`. With Increase Contrast on, `border` and `inkMuted` resolve to `ink`. | 1.4.3, 1.4.11 | U: compute ratios from `Palette.Settings` values |
| A2 | With System Settings › Keyboard › Keyboard navigation on, Tab reaches every enabled control in each pane in reading order, then wraps to the sidebar. Disabled controls are skipped. | 2.1.1, 2.4.3 | U: walk `nextValidKeyView`; M |
| A3 | In the sidebar, ↑ and ↓ change the section at once. Tab moves into the pane's first control, and focus doesn't jump when the pane changes. | 2.1.1, 3.2.1 | M |
| A4 | Every focused control shows the 2 pt ring of §3.2. A control focused below the fold is scrolled fully into view. | 2.4.7, 2.4.11 | M; U: `scrollToVisible` on focus |
| A5 | Space toggles checkboxes, Spread cells and buttons. ← and → move Top / Bottom. Return in the key field saves. Esc cancels recording. ⌘W closes the window. | 2.1.1 | M |
| A6 | Every clickable target is ≥ 24 × 24 pt. | 2.5.8 | U: frame sizes |
| A7 | VoiceOver reads name, role and value for each control: "Shortcut, Control-Option-I, button"; "Spread cell 7, checkbox, ticked"; "Top, radio button, selected, 1 of 2"; "Let AI tools add cards, checkbox, ticked"; "Copy setup for Codex, button". | 4.1.2 | U: `accessibilityLabel/Role/Value` |
| A8 | Every status change is announced with its prefix ("Warning: macOS also has a shortcut…"). | 4.1.3 | U: injected `announce` receives the string |
| A9 | No state is shown by color alone. A ticked cell has a check, the selected sidebar row is inverted and set in 600, statuses have a glyph and words, and a disabled control is also announced as dimmed. | 1.4.1 | M |
| A10 | Paste into the key field works, and nothing blocks the password manager. | 3.3.8 | U: paste into the field |
| A11 | No caption or status line is truncated at any length the code can produce. | 1.4.10 (spirit) | U: the longest string of each fits within 408 when wrapped |
| A12 | The pane's container has the section name as its accessibility label, so VoiceOver says "Shortcut" when the pane changes. | 2.4.6 | U |

---

## 5. Content and tone

Tone: concise, confident, helpful. Say what a control does and what follows from it, in the
present tense, with Ideator as the subject.

| Rule | Do | Don't |
| --- | --- | --- |
| Buttons use title case, start with a verb, and have ≤ 3 words | "Remove Key", "Check Now", "Reset to Default" | "OK", "Apply", "Clear", "Submit" |
| Checkboxes are in sentence case and name the on state | "Let AI tools add cards" | "Disable AI tools" |
| An error says what happened, then what to do | "⌘K can't be the shortcut. …" (today's) | "Error: invalid input" |
| Name the place | "Add one in Settings › AI Summary." | "Add one in Settings." |
| Explain jargon once | "…through MCP, a standard way for AI tools to reach apps." | "Configure the MCP server." |
| Ideator speaks as itself | "Ideator asks before it installs an update." | "We'll ask before installing." |
| No filler | "A key is saved." | "Your key was successfully saved!" |
| Typography | curly quotes “ ” ’, the ellipsis …, › for paths, key glyphs in macOS order ⌃⌥⇧⌘ | straight quotes, "...", ">" |

Messages elsewhere that point into Settings name the section, as text only, with no deep link (agreed
2026-10-29):

- "No API key. Add one in Settings." → "No API key. Add one in Settings › AI Summary."
- "Pick Spread cells in Settings" → "Pick Spread cells in Settings › Spread"

The strings in §3.13 were approved on 2026-10-30. The build updates CARDS-SPEC.md › Settings and the
tests that quote them in the same PR.

---

## 6. Anti-patterns and migration

### 6.1 Prohibited

| Do | Don't |
| --- | --- |
| `Palette.Settings.ink` | `NSColor(hex: 0x141413)` in a view, `.labelColor`, `.secondaryLabelColor` |
| Emphasis with weight 600 or a 1 pt underline | A clay or red word for emphasis |
| A status glyph plus `ink` text | Red text: "Invalid key" |
| Clay on ticked Spread cells only | Clay on Save, a link, the focus ring or the selected sidebar row |
| Flat, square, no shadow | `bezelStyle = .rounded`, `layer.cornerRadius = 6`, any `NSShadow` |
| The rounded bottom on Save only | The CTA shape on Check Now or Connect, or two primaries in one pane |
| The serif in the Privacy card only | A serif pane title or sidebar |
| `s1`…`s6` | 10, 18 or 20 pt gaps (today's values) |
| White inside input wells only | A white pane, card or button |
| The drawn 2 pt ring | The system's blue glow, or `focusRingType = .none` with nothing drawn |
| Wrapping text | Truncating with "…" or shrinking the font to fit |
| One tab stop for the Spread grid | 20 tab stops |
| Weights 400–600 | Weights 100–300 at any size used here |
| The agreed controls only | A new setting slipped in during the redesign |

### 6.2 Migration from today's Settings.swift

1. **Structure.** Replace the single scrolling `NSStackView` with a sidebar (`NSTableView`, six
   rows) and one pane view per section, swapped on selection. Keep `SettingsWindow`'s initializer
   unchanged, so `App.swift` and the tests still build it the same way.
2. **Window size.** "As tall as its rows, scrolling" becomes a fixed 640 × 640 (§2.5). Update
   CARDS-SPEC.md › Settings ("opens at the Shortcut row" becomes "opens on Shortcut") and the
   DESIGN.md row for `Settings.swift`.
3. **Headings.** `heading()` (bold 13) becomes the pane `title` (24/600) plus group labels (14/500).
   "API key (Anthropic or OpenAI)" becomes the label "API key", and its lead names both companies.
4. **Captions.** `caption()` (`secondaryLabelColor`, 11 pt) becomes `caption` 12 in `inkMuted`.
   Status text moves out of captions into status lines (§3.10).
5. **Controls.** Draw buttons, checkboxes, radios and cells with custom cells. Titles stay the same,
   so tests that find buttons by title keep working: "Use Default", "Remove Key", "Check Now",
   "Reset to Default", "Top", "Bottom", "Check for updates automatically", the tool names and
   "Copied".
6. **Spread cells.** 30 × 22 becomes 32 × 24. Twenty tab stops become one, with arrow keys. Labels
   stay "Spread cell N", so SpreadSettingsTests keeps passing. Add the checkbox role and value.
7. **Order inside sections.** MCP reorders: Connect first, then the checkbox and Top / Bottom, then
   the editor. Update `ConnectSettingsTests`' expected order (it lists "Bottom", "Instruction for AI
   tools", …, "Connect AI tools", "Claude Code"…) and the heading's new text.
8. **Privacy.** One paragraph becomes the card's list. Keep the phrase "whenever you click Check Now,
   Ideator asks GitHub whether a newer version exists", which SettingsTests asserts, or update that
   test together with the approved copy.
9. **Fonts.** Use `NSFont.monospacedSystemFont(ofSize:weight:)` (SF Mono). There is nothing to
   bundle or license.
10. **Spec changes (approved 2026-10-30):** the Keychain-refusal status line (§3.13, AI Summary),
    Save disabled while the field is empty (§3.4), and Remove Key disabled with no key (§3.12).
    Update CARDS-SPEC.md › Settings for all three, and check which SettingsTests click Remove Key
    or Save with no key.

---

## 7. QA checklist (for code review)

- [ ] No color literal outside `Palette.Settings`, and no `labelColor` or `secondaryLabelColor` in Settings.
- [ ] No spacing value outside `s1`…`s6`, and no font size outside 12/14/16/24.
- [ ] Clay appears only on ticked Spread cells. Searching for `accent` in Settings code finds one use.
- [ ] Exactly one primary button (Save). Its shape is 0/0/8/8, and every other corner in the window is 0.
- [ ] No `NSShadow`, no `cornerRadius`, no `NSVisualEffectView` in Settings.
- [ ] New York appears only in the Privacy card.
- [ ] The window is forced to `.aqua`, and it looks identical with Dark Mode on.
- [ ] Increase Contrast on: borders and captions turn `ink`.
- [ ] Every control in §3.1 has each listed state, checked by hovering, focusing, pressing and disabling it.
- [ ] Every focusable control shows the 2 pt ring. No blue system ring appears anywhere.
- [ ] Keyboard pass (A2–A5) with Keyboard navigation on: every pane, Tab order matching reading order, the Spread grid as one stop.
- [ ] VoiceOver pass: the A7 strings are read, and each status change is announced with its prefix (A8).
- [ ] Every target is ≥ 24 × 24 (A6).
- [ ] The longest caption and status string of each section wraps inside 408 with nothing truncated, and the MCP pane fits 640 without scrolling.
- [ ] The Privacy card names the saved key's company, and switches at once on Save and Remove Key.
- [ ] Opening Settings shows Shortcut. Closing and reopening shows Shortcut again.
- [ ] Every string matches §3.13 word for word. CARDS-SPEC.md, DESIGN.md and the tests are updated in the same PR.
- [ ] `run-ideator-tests` passes, and `verify-cards` screenshots each of the six panes.
