# Privacy

Ideator keeps your notes on your Mac. Over the network it sends a card's text to Anthropic or OpenAI, whichever company's API key you save, for a summary, only after you save your own key, and it asks GitHub once a day whether a newer version exists.

## What Ideator collects

Nothing. It has no analytics, no crash reporting, no account and no tracking. Ideator makes no network request other than the two described below.

## Where your data lives

- **Notes.** One Markdown file per card in `~/Documents/Ideator/`. The hidden file `.cards.json` in the same folder holds each card's place, the stack order, whether Clarity is on, the cached summaries, and the Spread set: which cards the Spread button made, where each goes back to, and the cells it was laid out for.
- **Shortcut.** Ideator's macOS preferences (`defaults read com.systemlabs.Ideator Shortcut`).
- **Spread cells.** `SpreadCells`, in the same preferences, lists the cells you ticked in Settings › Spread, by number. Ideator writes it the first time you tick or untick a cell.
- **Welcome window and tour.** `WelcomeSeen`, in the same preferences, holds the number of the last welcome you answered with one of its buttons. The number rises when the welcome's description of what leaves your Mac changes, and the new welcome then shows once. `TourSeen`, in the same preferences, is set to true when the welcome has offered you the tour, whether you started it or skipped it, so the tour does not start again by itself.
- **AI tools settings.** `AIToolsEnabled` (whether AI tools may add cards) and `AIToolsLanding` (`top` or `bottom`), in the same preferences. Ideator writes both the first time you change any AI tools setting in Settings, the instruction included. `AIToolsInstruction`, in the same preferences, is the text you edited in Settings' instruction box, from the first edit until you press Reset to Default or type the default text back. The helper an AI tool runs reads that key, so it can give the AI tool your text at the start of a session while Ideator is closed.
- **AI tools connection.** While Ideator runs, a socket file in your user's temporary folder (`getconf DARWIN_USER_TEMP_DIR`), `ideator-mcp.sock`, that only your user account can open. It carries the cards the helper an AI tool runs hands to Ideator, Ideator's answer to each, and the instruction text Ideator gives the helper when a session starts, and it holds no data itself. Ideator removes it when it quits; a file left by a crash is replaced at the next launch.
- **Update state.** Sparkle, the updater inside Ideator, keeps its state in the same preferences under keys that start with `SU`. They include `SULastCheckTime` (when it last asked GitHub), `SUHasLaunchedBefore`, `SUEnableAutomaticChecks` (once you change the checkbox in Settings) and `SUSkippedVersion` (once you skip a version).
- **API key.** Your login Keychain, under the service "Ideator" and the account "api-key". One item holds the last key you saved, from either company. It is never written to the notes folder or the preferences. A key that an earlier build saved under the account "anthropic-api-key" is not read and not deleted: paste the key again, and delete the old item in Keychain Access if you like.

## What leaves your Mac

### Summaries, to Anthropic or OpenAI

Only when a key is saved. The start of the key says whose it is: a key that starts with `sk-ant-` is Anthropic's, and any other key is OpenAI's. For each card with two or more non-blank body lines, Ideator sends the card's title and body as plain text, with the same instructions for both companies, and receives a summary. It does this for every such card, on the desktop or in the stack, collapsed or not, whenever the card has no summary for its text as it is now.

- An Anthropic key: the request goes to `https://api.anthropic.com/v1/messages` (model `claude-haiku-5-5`), with your key in the `x-api-key` header.
- Any other key: the request goes to `https://api.openai.com/v1/responses` (model `gpt-6-luna`), with your key in the `Authorization` header. The request sets `store` to false, so OpenAI is asked not to keep the response for later retrieval.

Nothing goes to the company whose key is not saved. A key from some other service is sent to OpenAI like any other key and is refused there.

Ideator keeps each summary in `.cards.json` and does not ask again while the summary matches the card. So it sends a card's text:

- a few seconds after you stop typing in the card, and when you press its refresh button;
- as soon as you switch back to Ideator after the card's file was changed or added in another app;
- the first time you switch back to Ideator after macOS lets it list a notes folder that it could not list at launch. Ideator then reads the folder again and takes in its cards as new, so it sends every card that was missing from the desktop and the stack, even one whose file did not change and whose saved summary still matches. The launch itself sends nothing, because a launch that cannot list the folder opens with no cards;
- when you save a key, for every card that has no summary yet, including cards whose last request failed. Saving a key for the other company counts the same way: summaries already written stay, and the rest are sent to the new company;
- at every launch, for every card that has no saved summary, and for every card whose file changed while Ideator was closed, because that card's saved summary is for the older text. A failed request is never saved, so a card whose request failed (no network, a rejected key, a rate limit) is sent again at the next launch. So is a card whose summary Ideator could not save, for example while `.cards.json` comes from a newer Ideator or macOS will not let Ideator list the notes folder;
- once more, for every card, after an update that changes the instructions Ideator sends with the text, because a saved summary is kept only if the same instructions wrote it.

The same unchanged text can therefore reach the company more than once, including after an edit that changes only a card's bold or italic formatting. The company's own terms cover what happens to the text once it arrives; see [Anthropic's page on how long it stores API data](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data) and [OpenAI's data controls for its API](https://developers.openai.com/api/docs/guides/your-data). Remove the key in Settings and Ideator stops sending anything to either.

### Update checks, to GitHub

Once a day, and whenever you click **Check Now** in Settings or **Check for Updates…** in the menu bar icon's menu, Ideator downloads `https://github.com/XingzhiC-starlight/ideator/releases/latest/download/appcast.xml`, a short file that names the newest version. The request carries no notes, no key and no system profile. GitHub sees your IP address and a user agent with the version you have (`Ideator/0.9 Sparkle/2.10.0`). If a newer version exists, Ideator asks you before it downloads and installs it.

The first check happens right after you press a button on the welcome window (**Start the tour**, **Skip the tour** or **Continue**), never before. If you used a build from before the welcome mentioned GitHub, it shows once more and nothing is sent until you press its button. A build that `scripts/package.sh` did not make never checks, and neither does a run started with `-CardsFolder`. The test copies that `scripts/verify-update.sh` makes are the one exception, and they ask only a server on your own Mac.

To turn the daily check off, clear **Check for updates automatically** in Settings. Ideator then asks GitHub only when you click **Check Now** or **Check for Updates…**. GitHub's own privacy statement covers its server logs.

### AI tools, on your Mac only

When an AI tool such as Claude Code, Codex or Claude Desktop adds a card, the connection is local: the tool runs a helper inside Ideator.app on your Mac, and the helper hands the card to Ideator, which saves it. Nothing new leaves your Mac. A card from an AI tool is saved like any other card and, with a key saved, sent for its summary like any other card. What the AI tool sends to its own servers, including the card it writes and the instruction and replies Ideator gives it, is covered by that tool's own terms. The buttons under Connect an AI tool in Settings › MCP only copy text to your clipboard, for you to paste into the tool. Ideator never edits an AI tool's config files.
