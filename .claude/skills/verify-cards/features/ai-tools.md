# AI tools (MCP)

An AI tool such as Claude Code, Codex or Claude Desktop runs Ideator's helper,
`Ideator.app/Contents/Helpers/ideator-mcp`, as an MCP server and calls its one tool, `add_card(title,
body?)`. The helper hands the card to the running Ideator, which saves it and answers where it went.
The card joins the stack: at the top, where the stack then shows it unless the user is typing in the
stacked card, or at the bottom, as Settings says. Settings also has a switch that turns the tool off.
When Ideator is not running, the helper starts it in the background.

## Sub-features

- `mcp-session` initialize, server/discover, tools/list and ping are answered by the helper alone, with no app started.
- `mcp-formats` A body with every list kind, nesting and bold/italic is saved as the card file's Markdown.
- `mcp-top` With Top, the card goes on top and the stack switches to it.
- `mcp-top-typing` With Top while the user types in the stacked card, the card goes on top and the stack stays.
- `mcp-top-settings` With Top while Settings is the key window, the stack switches: the user is not typing in it.
- `mcp-isolation` A helper given another folder never reaches the current run.
- `mcp-bottom` With Bottom, the card goes to the bottom and the stack stays.
- `mcp-hidden` Under Hide all the card is saved and counted, and nothing comes back on screen.
- `mcp-off` With "Let AI tools add cards" off, the reply is "Turned off in Ideator's Settings" and nothing is saved.
- `mcp-too-long` A title and body past 1 MB are refused with an error and nothing is saved.
- `mcp-launch` With Ideator not running, the helper starts it in the background and the card is saved.
- `mcp-welcome` While the welcome card waits for Continue, the card waits too: Continue within 40 s saves it, and
  after 40 s the reply says to press Continue and nothing is saved.
- `mcp-instruction` The instruction box in Settings: a fresh session's `initialize` returns the default text, then
  an edit, then the default again after Reset to Default, and nothing for a blank box. A helper for another folder
  keeps the default.
- `mcp-instruction-limit` The instruction box takes up to 100,000 bytes, refuses a change past that with a note above
  the box, and a text of the limit reaches a fresh session whole.
- `mcp-connect` Each Connect AI tools button copies its tool's setup, naming this build's helper and the run's
  `-CardsFolder`.

## How to get to it (user POV)

- An AI tool configured with the helper's path, asked to "put this in Ideator". Not driven here: the three-app
  check is the operator's, and this skill never edits an AI tool's config.
- Settings (the stack ribbon's ⋯ › Settings…, or ⌘,), rows "Let AI tools add cards" and "Cards from AI tools go
  to: Top / Bottom", after Updates. Under them the "Instruction for AI tools" box with "Reset to Default", then
  "Connect AI tools" with the buttons Claude Code, Codex and Claude Desktop, before Privacy.

## Driving it with cards-verify

Preconditions: `cv build` ran after the last change (it also compiles `cards-mcp`, the stand-in for an AI tool's
client). `cv mcp` and `cv mcp-launch` start the helper of the build `cv build` made, always with `-CardsFolder`
naming the run's temp folder, so it can only reach or start that run. `cv mcp-launch` takes the live-UI lock as
`cv launch` does, and `cv stop` releases it. Requests and replies are appended to `mcp.log` in the run's evidence
folder, with each card's title and body shown as lengths, as `log.txt` shows typed text. Write card bodies to files
under the run's evidence folder.

- **mcp-session.** Run `build/verify-tools/cards-mcp build/VerifyDerivedData/Build/Products/Debug/Ideator.app/Contents/Helpers/ideator-mcp -CardsFolder <a new temp folder> initialize discover list ping`.
  Each request has a reply, `serverInfo.name` is `ideator`, `instructions` is the spec's default text, and
  `pgrep -f -- "-CardsFolder <that folder>$"` prints nothing afterwards.
- **mcp-launch.** With no run up, record the owner's state, then run `cv mcp-launch initialize add 'Started by the
  helper'`. The reply reads `Added \"Started by the helper\" to the top of the stack.`, and `log.txt` names the pid the
  helper started and the frontmost app before and after, which must be the same app. `cv doctor` prints `healthy`
  for the adopted run; `cv shot` and `cv files` work on it as on a `cv launch` run.
- **mcp-formats.** `cv mcp add 'Formats' <body file>` with a body that has `- `, `* `, `1. `, `- [ ] `, `- [x] `,
  4- and 8-space nesting, `**bold**`, `*italic*`, a `# Heading` line and a code fence. Wait 1.5 s, then `cv files
  mcp-formats`: the card's `.md` has each list line, the nesting as 4 spaces per level, the styles, and the heading
  as `\# Heading`, a plain line.
- **mcp-top.** Flip the stack with `cv ax click stack 0.985 0.6` so it shows another card, `cv shot`, then `cv mcp add
  'Top switches'`. `cv ax tree` shows the new title in the stack's text area and the badge one higher.
- **mcp-top-typing.** `cv ax focus stack`, `cv ax type ' typed'`, then `cv mcp add 'Arrives while typing'` and `cv ax
  type ' more'`. `cv ax text stack` still shows the card typed in, ending ` typed more`; `.cards.json`'s `stack`
  has the new card first.
- **mcp-top-settings.** `cv ax key cmd+,` opens Settings, which takes the key window from the stack: the stack's
  format bar leaves `cv ax tree`. `cv mcp add 'Top while Settings is key'` then switches the stack to the new card.
- **mcp-bottom.** With Settings open, `cv ax act Bottom AXPress` (a radio button, which `press` does not find). Then
  `cv mcp add 'Bottom card'`: the reply says bottom, the stack still shows what it showed, the badge is one higher,
  and the new id is last in `.cards.json`'s `stack`.
- **mcp-hidden.** `cv ax act Top AXPress`, `cv ax press 'Hide all' stack`, `cv mcp add 'While hidden'`. `cv ax
  windows` lists the stack 46 points high, the badge in the ribbon counts the new card, and `cv files` has its file.
  `cv ax press 'Show all' stack`, and `cv ax text stack` shows the new card.
- **mcp-off.** In Settings, `cv ax act 'Let AI tools add cards' AXPress`, then `cv mcp add 'Should not exist'`: the
  reply is `Turned off in Ideator's Settings` with `"isError":true`, Top and Bottom are dimmed, and `cv files` lists
  no new file. Press it again to turn it back on.
- **mcp-too-long.** `cv mcp add-bytes 1000000`: title and body are 1,000,008 bytes, the reply is the 1 MB error with
  `"isError":true`, and no file is added.
- **mcp-isolation.** With a run up, run `cards-mcp` with `-CardsFolder` naming another new folder and `add
  'Isolation check'`: the reply says Added, the current run's folder gains nothing, and a second Ideator runs on the
  other folder. End it by its pid after checking its command line is this build on that folder.
- **mcp-welcome.** `cv stop`, then `CARDS_SHOW_WELCOME=1 CARDS_MCP_TIMEOUT=90 cv mcp-launch initialize add 'During
  welcome'`: the welcome card shows, and after about 40 s the reply says to press Continue and that nothing was
  saved, and no card file appears after Continue. For the two other outcomes, start `cards-mcp` with
  `CARDS_SHOW_WELCOME=1` on a new folder in the background, wait for the run's `Continue` button in `cards-ax
  tree <pid>`, then either `cards-ax press <pid> Continue` (the reply says Added and the folder has that card) or
  end the run by its pid (the reply says Ideator quit before it saved the card, and the folder has none).
- **mcp-instruction.** Record `defaults export com.systemlabs.Ideator - | shasum` first. `cv ax key cmd+,` opens
  Settings, which is `w0` while it is the front window (`cv ax tree` says). `cv mcp initialize` prints `instructions
  (412 characters)` and the default text. `cv ax focus w0` clicks into the box (the window's only text area),
  `cv ax key cmd+a`, `cv ax type 'Only save to-dos.\nUse a short title.'`; `cv ax text w0` shows both lines, and
  `cv mcp initialize discover` (a new helper, so a new session) prints that text for each. Next
  `build/verify-tools/cards-mcp <the build's helper> -CardsFolder <a new temp folder> initialize` prints the default and
  starts no app. `cv ax press "Reset to Default"`, then `cv mcp initialize` prints the default. `cv ax focus w0`, `cv
  ax key cmd+a`, `cv ax key delete`, then `cv mcp initialize` prints `instructions (none)`. Press Reset to Default
  again. The preferences hash is the same as at the start: a scratch run saves no edit.
- **mcp-instruction-limit.** `cv clip save` first, with Settings open. In one script, `cv clip set` a 120,000-byte
  text of `a` (made by `python3 -I -c`, never typed out), `cv ax focus w0`, `cv ax key cmd+a`, `cv ax key cmd+v`:
  `cv ax text w0` still shows the text from before, and `cv ax tree` shows the line above the box reading "That change
  would pass the 100 KB limit, so Ideator did not make it." The same with exactly 100,000 bytes: the box holds all of
  them, the line is its caption again, and `cv mcp initialize` prints `instructions (100000 characters)`. Press Reset to
  Default, then `cv clip restore`. Pipe `cv mcp` through `grep 'instructions ('` and `cut -c1-140`: it prints the
  whole text.
- **mcp-connect.** `cv clip save` first. `cv ax press "Claude Code" w0`, then `cv clip show` prints `claude mcp add
  --transport stdio --scope user ideator -- '<this build's .app>/Contents/Helpers/ideator-mcp' -CardsFolder
  <the run's folder>`. The same for `Codex` (a `[mcp_servers.ideator]` table with `command` and `args`) and `Claude
  Desktop` (a `mcpServers` object with an `ideator` entry). The button reads "Copied" for 2 seconds, and a `cv shot`
  in its own call starts later than that. Press and shoot in one script: `cv ax press Codex w0` then `cv shot copied`
  ran in 0.82 s on 2026-10-28, and its tree and its Settings png show the button reading "Copied" and the line above
  the buttons saying where to paste. `cv clip restore`, then `osascript -e 'clipboard
  info' | shasum` and `pbpaste | shasum` match their values from before `clip save`.

## Gotchas

- `cv clip show` prints whatever the clipboard holds: run it only after a press, never before, and never print the
  owner's clipboard.
- `cv mcp` prints the `instructions` of every initialize and discover reply in full on its own line; the reply
  line above it is cut at 300 characters.
- Never start the helper without `-CardsFolder`: with no normal Ideator of this build listening, it would start
  this build as a normal run, on the owner's `~/Documents/Ideator` and login Keychain.
- Run each step as its own command, after the last one returned. "Typing in the stacked card" is whatever the stack
  window holds at the moment of the call (key, with its format bar showing), so a Settings press that has not
  landed yet changes where a Top card goes.
- Find a run the helper started by the app binary and the folder (`^<binary> -CardsFolder <folder>$`): the helper's
  own command line also ends in `-CardsFolder <folder>`.
- `cv mcp-launch` has no `--seed`, and the app it starts has no `app.log`: Launch Services starts it, not `open
  --stdout`.
- The welcome card of a background start comes to the front with `orderFrontRegardless` and does not activate
  Ideator, so the frontmost app stays the same in `mcp-welcome` too. Frontmost alone proves little: macOS can
  refuse activation even to a foreground start. What tells the two apart is a press on Continue: in a foreground
  run (`cv launch --welcome`) Ideator is frontmost within about 60 ms of it, and a background run stays behind.
- `cv stop` ends the run with SIGTERM, and the app removes its socket file, `ideator-mcp-<hash>.sock`, in the
  user's temporary folder before it ends. SIGINT, SIGHUP, SIGKILL and a crash leave the file (the handler covers SIGTERM only); the next run that finds nothing answering on it replaces it.
- `mcp-isolation` names the folder as given; a helper given the same folder with `/private` in front, or in other
  letter case, reaches the same run.
- A first failed save (`chmod 555` the run's folder) answers the call at once with the "don't add it again" error,
  and the "Ideator can't save your notes" alert comes after it.
- Not verified here: that Claude Code, Codex and Claude Desktop pass the instruction to the model, the pasted setups
  inside those tools, the dimmed Connect buttons for an app on another volume or under `AppTranslocation` (a build here runs
  from a build folder; the unit tests open the window on such a path), a helper reading a normal (not scratch) run's
  saved preference, the three AI tools themselves,
  Gatekeeper on a downloaded build, and a normal (not scratch) run.
