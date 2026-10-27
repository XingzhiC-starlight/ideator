# Privacy

Ideator keeps your notes on your Mac. Over the network it sends a card's text to Anthropic for a summary, only after you save your own API key, and it asks GitHub once a day whether a newer version exists.

## What Ideator collects

Nothing. It has no analytics, no crash reporting, no account and no tracking. Ideator makes no network request other than the two described below.

## Where your data lives

- **Notes.** One Markdown file per card in `~/Documents/Ideator/`. The hidden file `.cards.json` in the same folder holds each card's place, the stack order, which cards are collapsed, and the cached summaries.
- **Shortcut.** Ideator's macOS preferences (`defaults read com.systemlabs.Ideator Shortcut`).
- **Update state.** Sparkle, the updater inside Ideator, keeps its state in the same preferences under keys that start with `SU`. They include `SULastCheckTime` (when it last asked GitHub), `SUHasLaunchedBefore`, `SUEnableAutomaticChecks` (once you change the checkbox in Settings) and `SUSkippedVersion` (once you skip a version).
- **API key.** Your login Keychain, under the service "Ideator". It is never written to the notes folder or the preferences.

## What leaves your Mac

### Summaries, to Anthropic

Only when a key is saved. For each card with two or more non-blank body lines, Ideator sends the card's title and body as plain text to `https://api.anthropic.com/v1/messages` (model `claude-haiku-5-5`), with your key in the `x-api-key` header, and receives a summary. It does this a few seconds after you stop typing in the card, after you change the key, and when you press a card's refresh button. The summary is cached in `.cards.json`, so it is not requested again until the text changes.

Anthropic's own terms and privacy policy cover what happens to the text once it arrives. Remove the key in Settings and Ideator stops sending anything to Anthropic.

### Update checks, to GitHub

Once a day, and whenever you click **Check Now** in Settings or **Check for Updates…** in the menu bar icon's menu, Ideator downloads `https://github.com/XingzhiC-starlight/ideator/releases/latest/download/appcast.xml`, a short file that names the newest version. The request carries no notes, no key and no system profile. GitHub sees your IP address and a user agent with the version you have (`Ideator/0.9 Sparkle/2.10.0`). If a newer version exists, Ideator asks you before it downloads and installs it.

The first check happens right after you press **Continue** on the welcome card, never before. A build that `scripts/package.sh` did not make never checks, and neither does a run started with `-CardsFolder`.

To turn the daily check off, clear **Check for updates automatically** in Settings. Ideator then asks GitHub only when you click **Check Now** or **Check for Updates…**. GitHub's own privacy statement covers its server logs.
