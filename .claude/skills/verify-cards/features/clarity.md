# Clarity

Clarity collapses cards to their header and an AI summary of up to three lines, at the same size and place.
It is one switch for every card, stacked and popped: the stack's Clarity button sets it, and no card
has a collapse state of its own. Clicking a collapsed card's body, New, and typing on the stack's
blank page turn it off.

## Sub-features

- `clarity-global-on` Clarity off → on collapses every card, the stacked one included.
- `clarity-global-off` Clarity on → off expands every card.
- `clarity-state` The ribbon button, the filter icon fourth from the left, is always named
  `Clarity`. Its value is `off` or `on`, its tooltip says what a click does, and its icon is a
  dark brown outline when off and a filled reddish brown circle when on.
- `clarity-click` Clicking a collapsed card's body turns Clarity off: every card expands, and the
  cursor goes into the clicked card.
- `clarity-new` New turns Clarity off, so the new card opens expanded with the cursor in it and every
  other card is expanded too.
- `clarity-blank` Typing the first character on the stack's blank page turns Clarity off the same way.
- `clarity-short-body` A card with an empty or one-line body shows that line instead of a summary.
- `clarity-no-key` Without an API key, a longer card shows `Summary unavailable`, with the reason
  `No API key. Add one in Settings.` on hover.
- `clarity-saved` The global state survives in the sidecar (`clarity`). The sidecar has no list of
  collapsed cards.
- `clarity-three-lines` A long summary wraps onto three lines and the third ends in `…`.
- `clarity-prompt-stamp` A saved summary shows only if the current prompt wrote it (its `prompt`
  stamp in the sidecar); any other is dropped and requested again.

## How to get to it (user POV)

- The Clarity icon (three lines in a circle) in the stack's ribbon.
- Clicking a collapsed card's body, on a popped card or on the stack's shown card.
- New in the ribbon, or typing on the stack's blank page.

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- Alpha shows on the stack, and `cv ax tree` shows Clarity with `value="off"`.

- **Global on.** Click Clarity. Run `cv shot clarity-off`, then `cv ax press Clarity stack`.
  `cv ax tree` shows the button still named `Clarity`, now with `value="on"` and the tooltip
  `Clarity is on: click to expand every card`. The stack has no `AXTextArea`, and two static
  texts: `Alpha card` and `alpha body` (a one-line body shows itself). The card has no collapse
  button, only `↗ Pop` and `Delete this card`. `cv shot clarity-on` shows the icon filled in reddish
  brown, where `clarity-off` shows a dark brown outline.
- **Saved.** Wait 1.5 s and run `cv files clarity`. The sidecar has `"clarity" : true` and no
  `collapsed` key.
- **Longer body.** Flip to Beta. Run `cv ax click stack 0.985 0.6`. `cv ax tree` shows
  `Beta card`, a `Refresh summary` button, and one of three summary lines. With no key stored it
  is `AXStaticText "No API key. Add one in Settings." value="Summary unavailable"`: the
  reason is the label's tooltip, which `tree` prints as its name. A key the API rejects gives the
  same value with the API's error as the reason, such as `HTTP 401: invalid x-api-key` from
  Anthropic or `HTTP 401: Incorrect API key provided: …` from OpenAI ([api-key](./api-key.md)). A
  working key gives a summary once one arrives. `cv shot clarity-beta` shows the summary line lighter than
  the header.
- **Popped card.** With Beta showing, run `cv ax press "↗ Pop" stack`. Beta arrives at `@0,34`
  collapsed, with no `AXTextArea`, and Alpha shows collapsed on the stack.
- **Click a body (`clarity-click`).** Run `cv ax click "card=Beta card" 0.5 0.8`, a real click on
  Beta's body. `cv ax tree` shows Clarity with `value="off"`, an `AXTextArea` in Beta's window that is
  `[focused]` and another in the stack, and `cv shot clarity-click` shows both expanded. The same
  click on the stack's collapsed card, `cv ax click stack 0.5 0.8`, does the same.
- **Global off.** Run `cv ax press Clarity stack` to turn Clarity on again, then once more. The
  button has `value="off"` and the tooltip `Clarity is off: click to collapse every card`, every
  card is expanded, and after 1.5 s `cv files clarity-off` shows `"clarity" : false` and no
  `collapsed` key.
- **New (`clarity-new`).** Run `cv ax press Clarity stack`, then `cv ax press New`. Clarity has
  `value="off"`, the new card's `AXTextArea` is empty and `[focused]`, and the other cards show
  their text areas too.
- **Blank page (`clarity-blank`).** Run `cv ax press Clarity stack`, then `cv ax click stack 0.985
  0.6` until `cv ax text stack` prints `""` (the blank page). Run `cv ax type 'X'`. Clarity has
  `value="off"` and the card holding `X` is expanded.

The body click, New and the blank page steps were written on 2026-10-29 and have not run yet.

- **Three lines and the stamp, without the API.** Write two sidecars that hold a long summary
  (over 150 characters) for `seed-b`, with `clarity` on: one stamped
  with `Summary.prompt`, one with another prompt's digest, such as `Digest(of: "another prompt")`.
  Build them by encoding `SavedDesk` from a `main.swift` compiled with
  `Cards/{Desk,Grid,Note}.swift`, using `Note(markdown:).digest` of Beta's seed text as `source`,
  so they always match the current code. Run
  `cv launch --seed stamped.json` and flip to Beta. `cv shot` shows the summary on three lines ending in `…`. Then `cv stop`,
  `cv launch --seed other-prompt.json`: Clarity is still on and Beta still collapsed, but Beta
  shows `Summary unavailable` (or a spinner with a working key), never the old text. A sidecar
  whose summary has no `prompt` at all no longer decodes and opens as no sidecar: Clarity off,
  both cards expanded in the stack. The stamped and unstamped pair passed on 2026-10-24; the
  other-prompt sidecar has not run yet.

## Gotchas

- A scratch run starts with no API key (it never reads the login Keychain), so Beta shows
  `Summary unavailable`. Pasting a working key into Settings makes Beta show a spinner and then real
  text from the API of the key's company (Anthropic or OpenAI), which costs a request. Use Alpha (one body line) when a
  deterministic proof is enough.
- A collapsed card has no text area, so `cv ax text` prints nothing for it, and
  `card=<title>` finds it by its header text instead.
- A sidecar written before 2026-10-29 can still list `collapsed` cards. Ideator ignores the list
  and the next save leaves it out.
- The refresh button (`Refresh summary`) appears on a collapsed card whose body has two or more
  lines, including while it shows `Summary unavailable`.
