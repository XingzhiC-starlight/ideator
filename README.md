# Ideator

A macOS prototype where every note is its own small window, laid out on an invisible 5 × 4 grid,
with a stack of the rest in the top-right corner. Native Swift and AppKit, no dependencies.
The behaviour is specified in [CARDS-SPEC.md](CARDS-SPEC.md); how the code is put together is in
[DESIGN.md](DESIGN.md).

Requires macOS 15 or later and Xcode 26.

## Open and run in Xcode

1. Open `Cards.xcodeproj`.
2. Pick the **Ideator** scheme and **My Mac** as the destination.
3. Press **⌘R**.

Ideator is a menu bar app, so it has no Dock icon. Look for the stacked-rectangles icon in the menu
bar: it has Show All, Hide All, Open Stack, Settings… and Quit. **⌃⌥I** hides or shows every card
from anywhere (Settings… changes it). Hide All leaves the stack's tan ribbon where the stack is, so
New, Clarity and the menu stay in reach. Opening Ideator again from Finder or Spotlight shows
everything.

On a MacBook with a crowded menu bar, macOS may hide the icon behind the camera notch. The stack's
tan ribbon has what you need: the eye button hides or shows everything (an open eye while cards
show, a slashed eye while they are hidden), and **⋯** at its right opens Settings… and Quit.

## Build from the command line

```bash
xcodebuild -project Cards.xcodeproj -scheme Ideator -configuration Debug -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Debug/Ideator.app
```

Run the unit tests (they use the app as their host and never touch `~/Documents/Ideator`):

```bash
xcodebuild test -project Cards.xcodeproj -scheme Ideator -derivedDataPath build/DerivedData
```

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
The script checks the app's signature, refuses an app that is not signed with the hardened runtime
or that carries the `get-task-allow` debug entitlement (either one lets other programs read the API
key from Ideator's memory), checks that the app has both `arm64` and `x86_64` slices and its icon,
and verifies the disk image. It runs from any folder, and running it again replaces the old image.

The app icon is a placeholder, drawn by `scripts/make-icon.swift` from the app's own colors. It gets
replaced before 1.0.

Send that one file. The other person needs a Mac with macOS 15 or later, Apple silicon or Intel.
They do this:

1. Open the dmg and drag **Ideator** to **Applications**.
2. Open Ideator from Applications. macOS blocks it, because Apple has not notarized the app.
3. Open **System Settings › Privacy & Security**, scroll to the message about Ideator, click **Open
   Anyway**, and confirm.
4. Ideator opens with a welcome card. Press **Continue**. If macOS then asks whether Ideator can
   access the Documents folder, allow it. Notes live in `~/Documents/Ideator`.
5. For summaries, choose **Settings…** from the menu bar icon and paste their own Anthropic API key.
   The image holds no key.

Each new version you send repeats the Open Anyway step. If they saved a key, macOS may also ask again
whether Ideator can read its Keychain item. They choose **Always Allow**.

## Where to paste the API key

Summaries use the Anthropic API (model `claude-haiku-5-5`). Click the menu bar icon (or **⋯** on
the stack's tan ribbon), choose **Settings…**, paste your key into **Anthropic API key**, and click **Save**.

The key is stored in your login Keychain (service "Ideator"), never in the project or the notes
folder. Without a key everything works; collapsed cards just say "Summary unavailable". Debug
builds are not signed with a stable identity, so after a rebuild macOS may ask once whether Ideator
may read its Keychain item; choose **Always Allow**.

[PRIVACY.md](PRIVACY.md) lists what Ideator stores and the one thing it sends.

## First launch

The first time Ideator starts, it shows a welcome card before it creates `~/Documents/Ideator`, so
macOS's Documents prompt comes after the card explains it. To see the card again, quit Ideator and
run `defaults delete com.systemlabs.Ideator WelcomeSeen`, or start it with the environment variable
`CARDS_SHOW_WELCOME=1` (`open --env CARDS_SHOW_WELCOME=1 /Applications/Ideator.app`). A run with
`-CardsFolder` shows no card on its own, remembers nothing, and does not register the global
shortcut.

## Where notes live

Each card is a Markdown file in `~/Documents/Ideator/`. Slot positions, stack order, collapsed
state and cached summaries live in the hidden file `~/Documents/Ideator/.cards.json`. To try the app
against another folder, pass `-CardsFolder /path/to/folder` as a launch argument (in Xcode: Product
› Scheme › Edit Scheme › Run › Arguments).

Builds from before the rename were called Cards and used `~/Documents/Cards` and the Keychain
service "Cards". Ideator does not read either: quit Cards, move the files (including the hidden
`.cards.json`) into `~/Documents/Ideator`, and paste the API key into Settings again.

## Using it

| To | Do |
| --- | --- |
| Make a card | **New** on the stack, or type on the stack's blank page |
| Select a stacked card | Swipe left or right with two fingers on the stack, or click the thin band along its edge: right/bottom = next, left/top = previous |
| Edit a stacked card | Click into it on the stack; it edits like any other card |
| Bring a card out | Select it, hover it and click **↗ Pop** |
| Move a card | Drag it by its title; it snaps to the nearest cell and swaps with whatever is there, or stays where you let go, even partly off the left, right or bottom edge |
| Put a card back | Hover it and click **↩ Stack** |
| Collapse to a summary | Hover a card and click the collapse button, or use **Clarity** on the stack for every card (its text turns reddish brown while on) |
| Format | ⌘B, ⌘I, or start a line with `- `, `1. ` or `[] `; the bar at the bottom of the card has the same five actions |

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
