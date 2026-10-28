# Updates

An installed Ideator build asks GitHub's feed for a newer build, offers it in Sparkle's window, and on
Install Update downloads it, checks the EdDSA signature of the feed and of the disk image, replaces
itself, and relaunches as the new build. A feed or a disk image signed by anyone else is refused with
an error and nothing changes on disk.

## Sub-features

- `updates-current` Check Now on the newest build says "You’re up to date!" and downloads nothing.
- `updates-offer` Check Now on an older build shows the offer with the two builds named.
- `updates-forged-feed` A feed signed by another key is refused before any disk image is requested.
- `updates-forged-image` A disk image that differs from what the feed signed is refused after the
  download, and the build on disk stays.
- `updates-install` Install Update, then Install and Relaunch, replaces the build and starts a new
  process of it.
- `updates-scheduled` A fresh install asks the feed by itself at launch and offers the update with no
  click.

## How to get to it (user POV)

- Settings (⌘,) › Updates › Check Now. It is user-initiated, so Sparkle answers every outcome with a
  window.
- The menu bar icon › Check for Updates…, which is Check Now from anywhere. After a scheduled check
  has found an update, it reads "Update to 0.9 (58)…".
- The daily scheduled check, which opens its window behind other apps.

## Driving it with cards-verify

Preconditions: `scripts/package.sh` made a disk image, and the terminal has Accessibility. `cv launch`
cannot reach this feature: a scratch run, and any build `cv build` makes, never starts Sparkle, and
Settings dims its update controls. Use the script, which launches its own copies of the shipped app
under a test bundle id and drives them with `cards-ax` by pid.

- **updates-all.** `scripts/verify-update.sh` runs the four phases below, prints a `PASS` line for each,
  then `PASS: the owner's Ideator is untouched`, and keeps its evidence in
  `build/verify-evidence/update-<time>/`. About 50 seconds. Below, N+1 is the shipped build number
  (the number of commits on `HEAD`, so it moves with every commit) and N is one less.
- **updates-current.** Phase `up to date`: `up-to-date.tree.txt` has `AXStaticText value="You’re up
  to date!"` and an `AXButton "OK"`, and `up-to-date.feed.log` has no `.dmg` request.
- **updates-forged-feed.** Phase `forged feed`: `forged-feed.tree.txt` has "Update Error!" and "The
  update feed is improperly signed and could not be validated", and its feed log has no `.dmg`.
- **updates-forged-image.** Phase `forged disk image`: the feed log has one `.dmg` request, and
  `forged-disk-image.tree.txt` has "The update is improperly signed and could not be validated".
- **updates-offer, updates-install.** Phase `real update`: `real-update-offer.tree.txt` has "A new
  version of Ideator is available!", "Ideator 0.9 (N+1) is now available—you have 0.9 (N).",
  `Install Update` and `Skip This Version`. `real-update-ready.tree.txt` has "Ready to Install" and
  `Install and Relaunch`. `real-update-relaunched.tree.txt` has the Settings line `Version 0.9 (N+1),
  commit …`, and `real-update-current.tree.txt` has "You’re up to date!" again.
- **updates-scheduled.** The same phase waits for the offer without pressing anything. Its `PASS` line
  says "offered by the scheduled check at launch".

## Gotchas

- The script takes `/tmp/claude-<uid>/ideator-live-ui.lock`, the lock that keeps one live Ideator
  session at a time. A run killed with `kill -9` leaves it behind: check that no Ideator session is
  running, then `rmdir` it.
- Pressing Install and Relaunch quits the app in the middle of the call, so `cards-ax press` reports
  an error for the press that worked. Look for the new process, not the exit status.
- An error alert's button is `Cancel Update`, not `OK`.
- The three phases before the real update turn scheduled checks off in the test copy's preferences
  (`SUEnableAutomaticChecks` is NO) and press Check Now, so each shows its result in a window. In the
  `real update` phase the check Sparkle makes at launch is left on. If it offers nothing within 30
  seconds the script says so, presses Check Now, and the `PASS` line says "offered by Check Now".
- On 2026-10-26 a connect from Ideator, and from a test tool, to `127.0.0.1:<port>` went unanswered
  for 7.8 seconds and failed, while `::1` was refused at once because nothing listened there. It did
  not happen again in the dozens of launches after it. The feed server therefore answers on `::1`
  too, and the feed names `localhost`, so the app connects over `::1`: each request line in
  `<phase>.feed.log` names the client address, and it reads `::1`. A check that still fails with
  "An error occurred in retrieving update information" is tried again up to three times, and the
  script says so.
- Not verified: the production key signing what the release feed lists, GitHub's real redirects, the
  menu bar icon's item (it has no handle for `cards-ax`; Settings' Check Now runs the same code), and
  Gatekeeper's prompts for a downloaded build.
