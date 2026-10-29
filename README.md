# Ideator

A macOS app where every note is its own small window, laid out on an invisible 5 × 4 grid,
with a stack of the rest in the top-right corner. Native Swift and AppKit, with one dependency,
[Sparkle](https://sparkle-project.org/), for updates. The behaviour is specified in
[CARDS-SPEC.md](CARDS-SPEC.md); how the code is put together is in [DESIGN.md](DESIGN.md).

Requires macOS 15 or later and Xcode 26.

## Open and run in Xcode

1. Open `Cards.xcodeproj`.
2. Pick the **Ideator** scheme and **My Mac** as the destination.
3. Press **⌘R**.

Ideator is a menu bar app, so it has no Dock icon. Look for the stacked-rectangles icon in the menu
bar: it has Show All, Hide All, Open Stack, Settings…, Check for Updates… and Quit. **⌃⌥I** hides
or shows every card from anywhere (Settings… changes it). Hide All leaves the stack's tan ribbon
where the stack is, so New, Clarity and the menu stay in reach. Opening Ideator again from Finder or
Spotlight shows everything.

On a MacBook with a crowded menu bar, macOS may hide the icon behind the camera notch. The stack's
tan ribbon has what you need: the eye button hides or shows everything (an open eye while cards
show, a slashed eye while they are hidden), and **⋯** at its right opens Settings… and Quit.

## Build from the command line

```bash
xcodebuild -project Cards.xcodeproj -scheme Ideator -configuration Debug -derivedDataPath build/DerivedData -disableAutomaticPackageResolution build
```

```bash
open build/DerivedData/Build/Products/Debug/Ideator.app
```

Run the unit tests (they use the app as their host and never touch `~/Documents/Ideator`):

```bash
xcodebuild test -project Cards.xcodeproj -scheme Ideator -derivedDataPath build/DerivedData -disableAutomaticPackageResolution
```

A failing run with its derived data under `~/Desktop` can hang on a macOS privacy prompt.
[run-ideator-tests](.claude/skills/run-ideator-tests/SKILL.md) runs the same tests from a copy
outside `~/Desktop`, runs one class or one test, and fails on a compiler warning in `Cards/`.

GitHub Actions ([ci.yml](.github/workflows/ci.yml)) runs on every pull request and every push to
`main`. It runs these tests, the desk invariant check and its mutants, and `scripts/package.sh`, and
it keeps the disk image as a downloadable artifact named `Ideator-dmg`.

## Share Ideator with someone

```bash
scripts/package.sh
```

This makes a Release build and writes `build/release/Ideator-<version>-<build>.dmg`. The version is
the app's `CFBundleShortVersionString` (`MARKETING_VERSION` in the project); the build number is the
number of commits on `HEAD`, so it rises with every release from `main` and needs a full clone.
The script stamps the app with the commit it builds from and whether the tree has uncommitted
changes, untracked files included, then reads both back from the finished app and stops if they
differ. It checks the app's signature, refuses an app that is not signed with the hardened runtime
or that carries the `get-task-allow` debug entitlement (either one lets other programs read the API
key from Ideator's memory), checks that the app has both `arm64` and `x86_64` slices and its icon,
and verifies the disk image. It also checks that `Sparkle.framework` is embedded at the version
`Package.resolved` pins, that `ThirdPartyNotices.txt` names it, and the signing policy below. It
checks the updater's settings in the app's `Info.plist`: the production feed, the release key,
system profiling and automatic installs off, no `IdeatorUpdateTest` flag and no
`NSAppTransportSecurity` exception. It checks that the AI tools helper, `Contents/Helpers/ideator-mcp`,
has the hardened runtime, the app's team, no debug entitlement and both slices. Then it runs the
packaged app once on an empty temporary folder, as a scratch run (no preferences, no shortcut, no
Keychain, no update check), and stops unless the app is still running after 3 seconds with Sparkle
loaded and has saved a card the helper handed it. A signature can verify and still belong to an app
macOS refuses to start. It runs from any folder, and running it again replaces the old image.

The app icon, a card and a spark on an ink plate, is drawn by `scripts/make-icon.swift` from the
app's own colors.

Send that one file. The other person needs a Mac with macOS 15 or later, Apple silicon or Intel.
They do this:

1. Open the dmg and drag **Ideator** to **Applications**.
2. Open Ideator from Applications. macOS blocks it, because Apple has not notarized the app.
3. Open **System Settings › Privacy & Security**, scroll to the message about Ideator, click **Open
   Anyway**, and confirm.
4. Ideator opens with a welcome card. Press **Continue**. If macOS then asks whether Ideator can
   access the Documents folder, allow it. Notes live in `~/Documents/Ideator`.
5. For summaries, choose **Settings…** from the menu bar icon and paste their own Anthropic or OpenAI API key.
   The image holds no key.

Each new version you send repeats the Open Anyway step. If they saved a key, macOS may also ask again
whether Ideator can read its Keychain item. They choose **Always Allow**.

## When the Developer ID arrives

Until a Team ID signs the build, the app is ad-hoc signed with the hardened runtime, and macOS then
refuses to load the Sparkle framework inside it ("different Team IDs"). The Release configuration
works around that with `Config/Ideator-adhoc.entitlements`, whose one entitlement turns library
validation off. With a Team ID the workaround has to go, and `scripts/package.sh` fails until it does.

1. Delete `Config/Ideator-adhoc.entitlements` (in Xcode, Move to Trash, which also drops its
   reference), and clear `CODE_SIGN_ENTITLEMENTS` on the Ideator target's Release configuration.
2. On that configuration set `CODE_SIGN_IDENTITY` to `Developer ID Application` and
   `DEVELOPMENT_TEAM` to the Team ID. Keep manual signing and the hardened runtime.
3. Run `scripts/package.sh`. Whatever Xcode did to the programs Sparkle ships inside its framework
   (`Autoupdate`, `Updater.app`, the XPC services), the script signs each again with the identity
   the app was built with, innermost first, then the framework, then the app, all before it checks
   anything. That needs the certificate in the keychain and Apple's timestamp server. The signing
   policy then wants no `disable-library-validation` entitlement and the app's Team ID on every
   Mach-O under `Contents/Frameworks`.
4. Run `scripts/verify-update.sh`. It seals its copies of the app with the shipped app's own identity
   and entitlements, so it passes with the ad-hoc build and with the Developer ID one.
5. TODO: notarize. `scripts/release.sh` does not notarize or staple anything yet. Add that between
   `scripts/package.sh` and `generate_appcast`, because stapling changes the disk image's bytes and
   the feed must sign the stapled file. Then the Open Anyway steps in "Share Ideator with someone"
   can go.

The Team ID path has not run with a real Developer ID yet. `scripts/test-signing.sh` checks the
order, identity and flags of every `codesign` call against a stand-in for `codesign`, in seconds and
without Xcode. The first run with the certificate is the real test.

## Check the summary prompt against a real key

```bash
scripts/check-summaries.sh
```

The script sends fourteen sample cards (English, Chinese and Japanese: to-do lists, thoughts, meeting
notes, links, a nested plan, thin cards) through the app's own request, using the key in
`$OPENAI_API_KEY` or one pasted at a hidden prompt, and checks each summary against the rules in
CARDS-SPEC.md § AI summaries that a program can check. `--anthropic` also runs the Anthropic request.
A rule marked (heuristic) can fire on a good summary, so it prints WARN and does not fail the run.
The script reads the key itself, before it compiles, so the prompt shows at once, nothing you paste is
echoed, and a key of any length (an `sk-proj-` key is over 128 characters) arrives whole. It then prints
one line with the key's company and length, such as "Read an OpenAI key, 164 characters.", so a cut or
empty paste shows before any request is sent. The key is never an argument and is never printed or
stored; the program gets it only through its environment. The cards are in
`scripts/check-summaries/main.swift`; none of yours are sent. When a rule fails, edit `Summary.instructions`
in `Cards/Desk.swift`, the one prompt for both companies, and run the script again.

## Is the installed app current?

```bash
scripts/installed-build.sh
```

The script reads the commit that `scripts/package.sh` stamped into `/Applications/Ideator.app` and
compares it with `origin/main`, which it fetches first. Pass another app's path to check that copy.
It prints one of these verdicts and exits 0 only for "current":

| Verdict | Meaning |
| --- | --- |
| current | The app was built from the tip of `origin/main`, or from a commit with the same files, as a branch build has after its squash merge. |
| behind by N commits | The app's commit is on `origin/main`, and N commits came after it. |
| not on origin/main | The app was built from a branch, or from before a squash merge. |
| not current | The app was built with local changes, so its files are not any commit's. |
| can't tell | The app has no stamp. It is older than the stamp, or `scripts/package.sh` did not make it. |

Settings shows the same stamp at the start of the caption under its Updates rows: `Version 0.9 (57),
commit 1a2b3c4`, `… with local changes`, or `Version 0.9 (1), a development build` for a build
without one, such as a run from Xcode. To read the stamp yourself:

```bash
defaults read /Applications/Ideator.app/Contents/Info.plist IdeatorCommit
defaults read /Applications/Ideator.app/Contents/Info.plist IdeatorTreeDirty
```

`IdeatorTreeDirty` is `YES` or `NO`. A build that did not come from `scripts/package.sh` carries
`none` and `unknown`, and `unknown` never means clean.

## Testing updates

```bash
scripts/package.sh
scripts/verify-update.sh
```

The second script proves, on this Mac, that an installed build updates itself to the next one through
Sparkle. It takes the app out of the newest disk image in `build/release` (or the one you pass), and
copies it twice as build N (one less than the shipped number) and N+1. The copies differ from the
shipped app in five `Info.plist` keys: the bundle id `com.systemlabs.Ideator.UpdateTest`, the build
number, a feed on `localhost`, the public half of a throwaway signing key, and `IdeatorUpdateTest`.
Each is sealed again with the app's own identity and entitlements (ad hoc with the one entitlement
today, the Developer ID and none later), and the script checks that its code is the shipped code.
A local server on `127.0.0.1` and `::1` (`scripts/test-feed-server.sh` checks that it answers on no
other address) then plays GitHub's `releases/latest/download` redirect, and N is launched four times
with a fresh preferences domain and `-CardsFolder` naming a temporary notes folder:

| Phase | The feed | Expected |
| --- | --- | --- |
| up to date | lists N | Check Now says "You're up to date!", no disk image requested |
| forged feed | N+1, signed by another key | Check Now says "The update feed is improperly signed", no disk image requested |
| forged disk image | N+1, one byte of the disk image flipped after signing | Check Now offers it, Install Update downloads it, then "The update is improperly signed", N stays |
| real update | N+1 | the check Sparkle makes at launch offers it with no click; if it has not within 30 seconds, Check Now does, and the `PASS` line names which one offered it. Then Install Update, Install and Relaunch, a new process running N+1 with the shipped code, and a Check Now that finds nothing |

It prints a `PASS` line per phase, then one for the owner: `/Applications/Ideator.app`, the
`com.systemlabs.Ideator` preferences, the running Ideator processes and `~/Documents/Ideator` are
hashed before and after and must not change. The test build keeps its state in its own preferences
domain, runs on a temporary notes folder, and gets a decoy `SUFeedURL` default that must never be
requested. Sparkle relaunches the new build without arguments, so just before that the script writes
the folder into the test domain as a `CardsFolder` default, which only an update-test copy honors.
Servers, test processes, that domain, its caches and the temporary files are removed on the way out,
even after a failure. Server logs, accessibility trees, screenshots and Sparkle's log are kept in
`build/verify-evidence/update-<time>/`.

It drives Sparkle's windows through Accessibility, as `verify-cards` does, so the terminal needs
that permission, the Mac has to be unlocked, and Ideator takes the focus while it runs. It takes
the lock the Claude sessions share (`/tmp/claude-<uid>/ideator-live-ui.lock`) so that only one of
them has a live Ideator open, and it does not run in CI. It does not prove that the release key signs
what the release feed lists, GitHub's real redirects, or the Gatekeeper prompts of a downloaded build.

## Releasing

A release is a GitHub release named `v<version>-<build>` that holds the disk image and `appcast.xml`,
the feed installed copies read. `SUFeedURL` in `Config/Info.plist` points at the newest published
release's `appcast.xml`, and Sparkle accepts a feed and a disk image only when they are signed with
the private key that matches `SUPublicEDKey` in the same file.

The one-time setup is done. The signing key is in the login Keychain (service
`https://sparkle-project.org`, account `ideator`), and its backup is in Apple Passwords as "Ideator
Sparkle update key". `gh` is logged in with `gh auth login`.

Each release, from `main` with nothing uncommitted and nothing newer on `origin/main`:

1. If the updater changed (`Updates.swift`, `Config/Info.plist`, `package.sh`, `signing.sh`,
   `release.sh` or the Sparkle version), run `scripts/package.sh` and then `scripts/verify-update.sh`.
2. Write the release notes as a few Markdown bullets in a file outside the checkout. The notes are
   shown in Sparkle's update window and on the GitHub release. A file inside the checkout would be
   untracked, and `release.sh` refuses an unclean tree.
3. Run `scripts/release.sh ~/Desktop/notes.md`. It runs `scripts/package.sh`, then checks that the
   Keychain's key is the one the built app trusts and that the live feed offers a lower build (no
   feed yet means this is the first release). It has Sparkle's `generate_appcast` sign the disk image
   and write a one-item `build/release/appcast.xml`, and parses that file: one item, the app's
   version and build, macOS 15.0 or later, the disk image's address and size, release notes and a
   signature. `sign_update --verify` then checks the signature of the disk image and of the feed.
   Last it creates a draft release with both files, downloads them back and compares them with the
   local ones, and prints the draft's address. macOS may ask whether `generate_appcast` and
   `sign_update` can use the key. Choose Always Allow. Installed copies cannot see a draft.
4. Read the draft on GitHub.
5. Run `scripts/release.sh --publish v0.9-<build>`, with the tag from step 3. It compares the draft's
   files with the local ones again, so a build made since cannot go out under the draft's name. It
   publishes the release as the latest one, then checks the feed for up to two minutes until it
   serves exactly the local `appcast.xml`. Installed copies below that build are offered the update
   at their next daily check, or at once through Check for Updates….

`scripts/release.sh --dry-run ~/Desktop/notes.md` stops after the checks in step 3 and writes
nothing to GitHub. Each run looks at what exists first, so running a command again carries on: an
existing draft gets the new files, and a release that is already live prints "already released".
A draft can be deleted on GitHub, but publishing cannot be taken back, because installed copies keep
a published build. The way back from a bad release is a higher build.

If the key is lost, installed copies cannot be updated again. They accept an update only when it is
signed by the key behind their `SUPublicEDKey`, and Sparkle can move a copy to a new key only when
the app is signed with a Developer ID, which these builds are not. Everyone would have to install the
next version by hand from a disk image. So restore the key from the Apple Passwords backup instead of
making a new one: `generate_keys --account ideator -f FILE`, with the tool from
`build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin` after `scripts/package.sh`.
`release.sh` stops when the Keychain's key is not the one in the app. Once a Developer ID signs the
app, see "When the Developer ID arrives" above.

## Where to paste the API key

Summaries use the Anthropic API (model `claude-haiku-5-5`) or the OpenAI API (model `gpt-6-luna`).
Click the menu bar icon (or **⋯** on the stack's tan ribbon), choose **Settings…**, paste your key into
**API key (Anthropic or OpenAI)**, and click **Save**. A key that starts with `sk-ant-` is Anthropic's and
any other key is OpenAI's; the line under the field says which one Ideator took. A key from another
service goes to OpenAI and fails there: the card shows "Summary unavailable" with HTTP 401 on hover.

The key is stored in your login Keychain (service "Ideator", account "api-key"), never in the project
or the notes folder. A key saved by a build from before 2026-10-28 sits under the account
"anthropic-api-key", which Ideator does not read: paste the key once more. Without a key everything works; collapsed cards just say "Summary unavailable". Debug
builds are not signed with a stable identity, so after a rebuild macOS may ask once whether Ideator
may read its Keychain item; choose **Always Allow**. A run started with `-CardsFolder` never reads
or writes the Keychain: it starts with no key, and a key pasted into Settings lasts until that run
quits.

[PRIVACY.md](PRIVACY.md) lists what Ideator stores and the two things it sends: a card's text to
Anthropic or OpenAI, whichever company's key you saved, whenever the card has no summary for its text
as it is now, and a daily update check to GitHub.

## AI tools

Ideator is an MCP server for AI tools such as Claude Code, Codex and Claude Desktop. The server is
the helper inside the app, `Ideator.app/Contents/Helpers/ideator-mcp`, which an AI tool runs over
stdio. Its one tool, `add_card`, hands a card to the running Ideator, which saves it to the stack;
if Ideator is not running, the helper starts it in the background. Settings has "Let AI tools add
cards" and "Cards from AI tools go to: Top / Bottom", an editable instruction that the server gives an
AI tool when a session starts (with Reset to Default), and under "Connect AI tools" a copy button for
Claude Code, Codex and Claude Desktop. Each button copies the tool's setup, naming this app's helper,
for you to paste; Ideator never edits another app's config files. To try it without touching your notes, give the helper the same `-CardsFolder` as a
scratch run: it then reaches, or starts, only the run on that folder. The verify-cards recipe
[ai-tools.md](.claude/skills/verify-cards/features/ai-tools.md) drives it with a stand-in client.

## First launch

The first time Ideator starts, it shows a welcome card before it creates `~/Documents/Ideator`, so
macOS's Documents prompt comes after the card explains it. An update shows the card once more when
it now says something new about what Ideator sends. To see the card again, quit Ideator and
run `defaults delete com.systemlabs.Ideator WelcomeSeen`, or start it with the environment variable
`CARDS_SHOW_WELCOME=1` (`open --env CARDS_SHOW_WELCOME=1 /Applications/Ideator.app`). A run with
`-CardsFolder` shows no card on its own, remembers nothing, does not register the global shortcut,
and never checks for updates, except in the test copies `scripts/verify-update.sh` makes.

## Where notes live

Each card is a Markdown file in `~/Documents/Ideator/`. Slot positions, stack order, collapsed
state and cached summaries live in the hidden file `~/Documents/Ideator/.cards.json`. To try the app
against another folder, pass `-CardsFolder /path/to/folder` as a launch argument (in Xcode: Product
› Scheme › Edit Scheme › Run › Arguments). Only the argument counts: a `CardsFolder` key in
Ideator's preferences changes nothing.

Builds from before the rename were called Cards and used `~/Documents/Cards` and the Keychain
service "Cards". Ideator does not read either: quit Cards, move the files (including the hidden
`.cards.json`) into `~/Documents/Ideator`, and paste the API key into Settings again. A
`.cards.json` from a build before 2026-10-22 (version 1), or from a build before 2026-10-24 with any
summary in it, opens as if there were none: every card in the stack, with no places, Clarity or
collapsed cards, and the first save replaces it. The notes themselves are kept.

## Using it

| To | Do |
| --- | --- |
| Make a card | **New** on the stack, or type on the stack's blank page |
| Select a stacked card | Swipe left or right with two fingers on the stack, or click the thin band along its edge: right/bottom = next, left/top = previous |
| Edit a stacked card | Click into it on the stack; it edits like any other card |
| Bring a card out | Select it, hover it and click **↗ Pop** |
| Move a card | Drag it by its title or by the margin around its text. Let go close to a cell's center (within 15 % of a cell) and it snaps into that cell, and a card or the stack snapped there trades places with it; let go anywhere else and it stays exactly there, over other cards, even partly off the left, right or bottom edge |
| Put a card back | Hover it and click **↩ Stack** |
| Reorder the stack | Click the count badge in the stack's corner, then drag a card's row by its grip (≡), or select a row and press ⌥↑ or ⌥↓ |
| Collapse to a summary | Hover a card and click the collapse button, or use **Clarity** on the stack for every card (its text turns reddish brown while on) |
| Hide every card | Click the eye on the stack's ribbon, press ⌃⌥I, or choose **Hide All** from the menu bar icon; the stack shrinks to its ribbon, and the same again shows everything |
| Format | ⌘B, ⌘I, or start a line with `- `, `* `, `1. `, `[] ` or `[ ] `; the bar at the bottom of the card has the same five actions |
| Nest a list item | **Tab** moves it one level deeper, up to three levels, and **Shift-Tab** one level up |
| Copy and paste | ⌘C on a selection inside one line copies just its text. A selection across a line break copies every line it touches as Markdown and as an HTML list, so Notes and Mail paste a real list and Markdown apps paste Markdown; ⌘V reads lists from Notes, web pages, the Claude app and terminal output |

The stack is a loop with one blank page after the last card. Swiping past the last card shows the
blank page, and swiping once more shows the top card again. Typing on the blank page makes a new
card at the bottom of the stack; leaving it empty makes nothing.

## License

Ideator (formerly Cards) is source-available under the
[PolyForm Shield License 1.0.0](LICENSE.md), not an open source license. You may use, change and
share it for any purpose, including at work, except to offer a product that competes with it. The
name and icon are not covered by the license; see [TRADEMARKS.md](TRADEMARKS.md).

Contributions are welcome. Contributors sign the [Contributor License Agreement](CLA.md) once; see
[CONTRIBUTING.md](CONTRIBUTING.md).
