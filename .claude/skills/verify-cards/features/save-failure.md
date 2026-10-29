# Saving fails

When Ideator can't write its notes folder (Don't Allow on the Documents prompt, a read-only or
ejected volume), the first failed save shows "Ideator can't save your notes", with the System
Settings hint when the folder is inside Documents. Edits stay in memory and every later save
retries. Quitting while a save still fails asks "Quit without saving?", with Cancel and Quit
Anyway; once the folder is writable again, the next save or quit writes everything and asks
nothing. Two more cases protect the sidecar: one written by a newer Ideator, found at launch or at
a later save, is left alone and a notice says so once per run; a folder that can't be listed at
launch opens empty, says so once, and never has its sidecar overwritten.

## Sub-features

- `save-alert` The first failed save shows the alert once; later failures are silent until a save
  succeeds.
- `quit-asks` ⌘Q while the save still fails asks; Cancel keeps Ideator and the unsaved text in
  memory; Quit Anyway ends it with nothing more written.
- `quit-saves` Once the folder is writable again, ⌘Q saves and asks nothing.
- `newer-sidecar-later` A version-3 sidecar that appears while Ideator runs is left byte for byte,
  and the "arranged by a newer Ideator" notice shows at the next save.
- `unread-folder` A folder that can't be listed at launch: notice at launch, sidecar never written.
  Not drivable here (`cv launch` creates a listable folder); `DeskControllerTests` and
  `LibraryTests` pin it.

## How to get to it (user POV)

- Any save after the folder stops accepting writes; saves run one second after a change and when
  Ideator resigns active.
- Quit: ⌘Q while Ideator is active, Quit Ideator in the menu bar icon's menu, or in the ribbon's ⋯
  menu.

## Driving it with cards-verify

Preconditions:

- `cv build` ran after the last source change, and `cv launch --seed` started the run.
- `source build/verify-runs/current.env` gives `$FOLDER`, the run's card folder. Each launch has a
  new folder and the Bash tool keeps no variable between calls, so source it again in every call
  that uses `$FOLDER`.

- **save-alert.** `cv ax press New`, `cv ax type 'Quit test'`, wait 1.5 s, `cv files typed` shows the
  new card's file. `chmod 555 "$FOLDER"`, then `cv ax type ' more'` and wait 2 s. `cv ax tree` shows
  the static text "Ideator can't save your notes" and an `OK` button; `cv shot save-failed`; `cv ax
  press OK`.
- **quit-asks.** `cv ax key cmd+q`, wait 1 s. `cv ax tree` shows "Quit without saving?" with
  buttons `Cancel` and `Quit Anyway`; `cv shot quit-asks`. `cv ax press Cancel`: `cv doctor` still
  prints `healthy`, and `cv files after-cancel` shows the file without " more". Then `cv ax key
  cmd+q` again and `cv ax press "Quit Anyway"`: the pid is gone within a second. `chmod 755
  "$FOLDER"`; the file still lacks " more". `cv stop` cleans up.
- **quit-saves.** A new `cv launch --seed`. `cv ax press New`, type, wait 1.5 s, `chmod 555
  "$FOLDER"`, type more, wait 2 s, `cv ax press OK`, `chmod 755 "$FOLDER"`, `cv ax key cmd+q`. The
  pid is gone with no alert, and the card's file holds the whole text.
- **newer-sidecar-later.** quit-saves ended its run, so `cv stop` and a new `cv launch --seed` first.
  `cv ax press "↗ Pop"`, wait 1.5 s, `cv files popped` shows a
  `"version" : 2` sidecar with Alpha's placement. Write
  `{"version":3,"layout":{"kind":"from a newer Ideator"}}` over `$FOLDER/.cards.json` (here the
  edit is the scenario itself, another Mac's write, not a shortcut). `cv ax press "↗ Pop"` again and
  wait 2 s: `cv ax tree` shows "These notes were arranged by a newer Ideator" and `OK`; `cv shot`;
  `cv ax press OK`. `cv files after-newer` shows the version-3 bytes unchanged, and `cv shot` shows
  both cards popped.

## Gotchas

- The alerts are app-modal: until `OK`, `Cancel` or `Quit Anyway` is pressed, nothing else in the
  app answers. A stuck run ends with `cv stop`.
- `chmod 555` must come after the new card's first save, or the card itself fails to save: a
  valid variant, but a different proof.
- Restore the folder (`chmod 755 "$FOLDER"`) before `cv stop`, which deletes it.
- The ribbon's ⋯ menu does not answer `cv ax press`; quit with `cv ax key cmd+q`, which activates
  Ideator first.
