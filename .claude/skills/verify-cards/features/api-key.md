# API key

Settings › AI Summary has one field for an Anthropic or an OpenAI key. The line under the field says
whose key is held, the card in Settings › Privacy names the same company, and a collapsed card whose
summary the company refuses shows `Summary unavailable` with that company's HTTP 401 on hover. A key
that starts with `sk-ant-` is Anthropic's and any other key is OpenAI's.

## Sub-features

- `key-none` With no key, the status line says so, the privacy card names both companies, and a
  collapsed card with two body lines shows `Summary unavailable` with `No API key. Add one in Settings › AI Summary.`
- `key-openai` A key that does not start with `sk-ant-` gives `An OpenAI key is held for this run only.`
  and a privacy card naming OpenAI alone. The collapsed card asks OpenAI and shows its HTTP 401.
- `key-anthropic` A key that starts with `sk-ant-` replaces it: the lines name Anthropic, the failed
  summary is asked again, and the hover now shows Anthropic's `HTTP 401: invalid x-api-key`.
- `key-removed` Remove Key puts the none lines back, and the card says `No API key.` again.
- `key-unsaved` The sidecar's `summaries` stays empty after every failure.

## How to get to it (user POV)

- **Settings…** in the menu bar icon's menu or the stack ribbon's ⋯ menu (not driven), or ⌘, while
  Ideator is active, then **AI Summary** in the sidebar. Settings opens on Shortcut with the sidebar
  focused, so Tab moves the caret into the key field.

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- Fake keys only. Each paste sends Beta's text (the seeded card with two body lines; Alpha's one line
  is never sent) to api.openai.com or api.anthropic.com with an invalid key, which answers 401.
  Never paste a real key, and a scratch run never touches the Keychain.

- **key-none.** `cv ax press Clarity stack`, then `cv ax click stack 0.985 0.6` to show Beta.
  `cv ax tree` has `AXStaticText "No API key. Add one in Settings › AI Summary." value="Summary unavailable"`. Open
  Settings with `cv ax key cmd+,`, then `cv ax section "AI Summary"`. `cv ax tree` shows the label `API
  key`, the line `No key saved. …`, and `Remove Key` and `Save` both `[disabled]`. `cv shot key-none` is
  the proof image. `cv ax section Privacy`: the card's first text starts `With a key saved, Ideator
  sends a card's text to Anthropic or OpenAI, whichever your key is for`. Go back with `cv ax section
  "AI Summary"`, then `cv ax key tab` puts the caret in the key field.
- **key-openai.** `cv ax type 'sk-proj-fakefakefakefakefake'` (Save is enabled once the field has
  text), then `cv ax press Save`, and wait 4 s.
  The status line reads `An OpenAI key is held for this run only. Paste a new one to replace it.`,
  Remove Key is enabled, the privacy card (`cv ax section Privacy`) says `… sends a card's text to
  OpenAI, using your own key`, and Beta's static text is
  `AXStaticText "HTTP 401: Incorrect API key provided: sk-proj-****************fake. …" value="Summary
  unavailable"`. OpenAI's own message echoes the pasted key with the middle masked.
- **key-anthropic.** `cv ax section "AI Summary"`, `cv ax key tab`, `cv ax type 'sk-ant-fakefakefakefakefake'`,
  `cv ax press Save`, wait 4 s. The status line starts `An Anthropic key is held`, the privacy card
  `… to Anthropic, using your own key`, and Beta's reason is `HTTP 401: invalid x-api-key`.
- **key-removed.** In AI Summary, `cv ax press "Remove Key"`. The none lines are back, Remove Key is
  `[disabled]` again, and Beta says `No API key.`.
- **key-unsaved.** After 1.5 s, `cv files key-after` shows an empty `summaries` list.

## Gotchas

- A scratch run keeps the key in memory only, so the status line says `held for this run only`, never
  `saved in your Keychain`. The Keychain path is not driven by this harness.
- The 401 comes from the real servers: it needs the network, and a slow network shows the spinner
  longer than 4 s.
- A key with no `sk-ant-` start is OpenAI's whatever service issued it, so a Kimi or Qwen key fails
  with OpenAI's 401.
- Only the shown section is in `cv ax tree`, so read the privacy card after `cv ax section Privacy` and
  the key's lines after `cv ax section "AI Summary"`. Typing goes to the focused view: after a section
  change that is the sidebar, so press Tab before typing a key.
