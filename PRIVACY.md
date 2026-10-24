# Privacy

Ideator keeps your notes on your Mac. It sends nothing anywhere until you save an Anthropic API key, and then it sends only what a summary needs.

## What Ideator collects

Nothing. It has no analytics, no crash reporting, no account and no tracking. Ideator makes no network request other than the summary request described below.

## Where your data lives

- **Notes.** One Markdown file per card in `~/Documents/Ideator/`. The hidden file `.cards.json` in the same folder holds each card's place, the stack order, which cards are collapsed, and the cached summaries.
- **Shortcut.** Ideator's macOS preferences (`defaults read com.systemlabs.Ideator Shortcut`).
- **API key.** Your login Keychain, under the service "Ideator". It is never written to the notes folder or the preferences.

## What leaves your Mac

Only when a key is saved. For each card with two or more non-blank body lines, Ideator sends the card's title and body as plain text to `https://api.anthropic.com/v1/messages` (model `claude-haiku-5-5`), with your key in the `x-api-key` header, and receives a summary. It does this a few seconds after you stop typing in the card, after you change the key, and when you press a card's refresh button. The summary is cached in `.cards.json`, so it is not requested again until the text changes.

Anthropic's own terms and privacy policy cover what happens to the text once it arrives. Remove the key in Settings and Ideator stops sending anything.
