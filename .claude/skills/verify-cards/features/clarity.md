# Clarity

Clarity collapses cards to their header and an AI summary of up to three lines, at the same size and place.
The stack's Clarity button collapses or expands every card, stacked and popped. Each card's own
button collapses or expands just that card, and the card keeps its state when it moves.

## Sub-features

- `clarity-global-on` Clarity off → on collapses every card, the stacked one included.
- `clarity-global-off` Clarity on → off expands every card.
- `clarity-state` The ribbon button always reads `Clarity`. Its value is `off` or `on`, its tooltip
  says what a click does, and its text color is soft brown when off and reddish brown when on.
- `clarity-card` A card's collapse/expand button changes only that card, not the global button.
- `clarity-short-body` A card with an empty or one-line body shows that line instead of a summary.
- `clarity-no-key` Without an API key, a longer card shows `Summary unavailable`, with the reason
  on hover.
- `clarity-saved` Collapsed cards and the global state survive in the sidecar.
- `clarity-three-lines` A long summary wraps onto three lines and the third ends in `…`.
- `clarity-prompt-stamp` A saved summary shows only if the current prompt wrote it (its `prompt`
  stamp in the sidecar); any other is dropped and requested again.

## How to get to it (user POV)

- `Clarity` in the stack's ribbon.
- The collapse button on a card (fades in on hover), and on the stack's shown card.
- Clicking a collapsed card's body expands it (not driven: use the button).

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- Alpha shows on the stack, and `cv ax tree` shows Clarity with `value="off"`.

- **Global on.** Click Clarity. Run `cv shot clarity-off`, then `cv ax press Clarity stack`.
  `cv ax tree` shows the button still named `Clarity`, now with `value="on"` and the tooltip
  `Clarity is on: click to expand every card`. The stack has no `AXTextArea`, and two static
  texts: `Alpha card` and `alpha body` (a one-line body shows itself). The card button reads
  `Expand this card`. `cv shot clarity-on` shows the same word in reddish brown instead of soft
  brown; crop and enlarge the ribbon to compare the two PNGs.
- **Longer body.** Flip to Beta. Run `cv ax click stack 0.985 0.6`. `cv ax tree` shows
  `Beta card`, a `Refresh summary` button, and one of three summary lines. With no key stored it
  is `AXStaticText "No Anthropic API key. Add one in Settings." value="Summary unavailable"`: the
  reason is the label's tooltip, which `tree` prints as its name. A key the API rejects gives the
  same value with the API's error as the reason, such as `HTTP 401: invalid x-api-key`. A working
  key gives a summary once one arrives. `cv shot clarity-beta` shows the summary line lighter than
  the header.
- **One card.** Expand only Beta. Run `cv ax press "Expand this card" stack`. The stack's
  `AXTextArea` is back with Beta's text, the card button reads `Collapse this card`, and Clarity
  still has `value="on"`.
- **Saved.** Wait 1.5 s and run `cv files clarity`. The sidecar has `"clarity" : true` and
  `collapsed` lists `seed-a` only.
- **Global off.** Click Clarity again. Run `cv ax press Clarity stack`. The button has
  `value="off"` and the tooltip `Clarity is off: click to collapse every card`, every card is
  expanded, and after 1.5 s `cv files clarity-off` shows `"clarity" : false` and an empty
  `collapsed`.

- **Three lines and the stamp, without the API.** Write two sidecars that hold a long summary
  (over 150 characters) for `seed-b`, with `clarity` on and both cards collapsed: one stamped
  with `Summary.prompt`, one without `prompt`. Build them by encoding `SavedDesk` from a
  `main.swift` compiled with `Cards/{Desk,Grid,Note}.swift`, using `Note(markdown:).digest` of
  Beta's seed text as `source`, so they always match the current code. Run
  `cv launch --seed stamped.json` and flip to Beta (collapse it with its button if it shows
  expanded). `cv shot` shows the summary on three lines ending in `…`. Then `cv stop`,
  `cv launch --seed unstamped.json`: Beta shows `Summary unavailable` (or a spinner with a
  working key), never the old text. On 2026-10-24 both passed.

## Gotchas

- A scratch run starts with no API key (it never reads the login Keychain), so Beta shows
  `Summary unavailable`. Pasting a working key into Settings makes Beta show a spinner and then real
  text from the Anthropic API, which costs a request. Use Alpha (one body line) when a
  deterministic proof is enough.
- A collapsed card has no text area, so `cv ax text` prints nothing for it, and
  `card=<title>` finds it by its header text instead.
- The refresh button (`Refresh summary`) appears on a collapsed card whose body has two or more
  lines, including while it shows `Summary unavailable`.
