# API key

Settings has one field for an Anthropic or an OpenAI key. The line under the field says whose key is
held, the privacy line at the bottom of Settings names the same company, and a collapsed card whose
summary the company refuses shows `Summary unavailable` with that company's HTTP 401 on hover. A key
that starts with `sk-ant-` is Anthropic's and any other key is OpenAI's.

## Sub-features

- `key-none` With no key, the status line says so, the privacy line names both companies, and a
  collapsed card with two body lines shows `Summary unavailable` with `No API key. Add one in Settings.`
- `key-openai` A key that does not start with `sk-ant-` gives `An OpenAI key is held for this run only.`
  and a privacy line naming OpenAI alone. The collapsed card asks OpenAI and shows its HTTP 401.
- `key-anthropic` A key that starts with `sk-ant-` replaces it: the lines name Anthropic, the failed
  summary is asked again, and the hover now shows Anthropic's `HTTP 401: invalid x-api-key`.
- `key-removed` Remove Key puts the none lines back, and the card says `No API key.` again.
- `key-unsaved` The sidecar's `summaries` stays empty after every failure.

## How to get to it (user POV)

- **Settings…** in the menu bar icon's menu or the stack ribbon's ⋯ menu (not driven), or ⌘, while
  Ideator is active. The key field has the caret when Settings opens.

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- Fake keys only. Each paste sends the seeded card text to api.openai.com or api.anthropic.com with an
  invalid key, which answers 401. Never paste a real key, and a scratch run never touches the Keychain.

- **key-none.** `cv ax press Clarity stack`, then `cv ax click stack 0.985 0.6` to show Beta.
  `cv ax tree` has `AXStaticText "No API key. Add one in Settings." value="Summary unavailable"`. Open
  Settings with `cv ax key cmd+,`. `cv ax tree` shows the heading `API key (Anthropic or OpenAI)`, the
  line `No key saved. …`, and a privacy line starting `With a key saved, Ideator sends a card's text to
  Anthropic or OpenAI, whichever your key is for`. `cv shot key-none` is the proof image.
- **key-openai.** `cv ax type 'sk-proj-fakefakefakefakefake'`, then `cv ax press Save`, and wait 4 s.
  The status line reads `An OpenAI key is held for this run only. Paste a new one to replace it.`, the
  privacy line starts `… sends a card's text to OpenAI, using your own key`, and Beta's static text is
  `AXStaticText "HTTP 401: Incorrect API key provided: sk-proj-****************fake. …" value="Summary
  unavailable"`. OpenAI's own message echoes the pasted key with the middle masked.
- **key-anthropic.** `cv ax type 'sk-ant-fakefakefakefakefake'`, `cv ax press Save`, wait 4 s. The status
  line starts `An Anthropic key is held`, the privacy line `… to Anthropic, using your own key`, and
  Beta's reason is `HTTP 401: invalid x-api-key`.
- **key-removed.** `cv ax press "Remove Key"`. The none lines are back and Beta says `No API key.`.
- **key-unsaved.** After 1.5 s, `cv files key-after` shows an empty `summaries` list.

## Gotchas

- A scratch run keeps the key in memory only, so the status line says `held for this run only`, never
  `saved in your Keychain`. The Keychain path is not driven by this harness.
- The 401 comes from the real servers: it needs the network, and a slow network shows the spinner
  longer than 4 s.
- A key with no `sk-ant-` start is OpenAI's whatever service issued it, so a Kimi or Qwen key fails
  with OpenAI's 401.
