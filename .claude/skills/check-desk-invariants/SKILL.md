---
name: check-desk-invariants
description: Exhaustively check the Cards desk rules (Cards/Desk.swift, with Grid.swift and Note.swift) against eight promises (no card lost or duplicated, valid places, the stack page, stack order, save-and-reload, Clarity, summaries, Spread) over every sequence of up to 3 commands. Use whenever a change touches Desk.swift, Grid.swift, Note.swift, the Command enum, SavedDesk or how the sidecar is read, before saying the change is safe.
---

# Check the desk invariants

Every change to Cards' state goes through one pure function, `Desk.apply(_ Command)` in
`Cards/Desk.swift`. `Library.save` then makes the folder match the desk, and a card missing from
the desk is a file it moves to the Trash. So a rule that drops a card, even in one unusual
order of clicks, deletes a user's note. Unit tests in `CardsTests/DeskTests.swift` check the
sequences someone wrote down. This check runs **every** sequence, within a stated bound.

## What it checks

`check/main.swift` compiles together with the real `Cards/Desk.swift`, `Grid.swift` and
`Note.swift`, no copies and no model. It starts from six desks, built by `Desk(notes:saved:)` as
a launch builds them:

- `empty`: no cards.
- `three stacked`: cards b, a, c in the stack.
- `mixed`: Clarity on, the stack at a free point, one card snapped to slot 0, one free, one stacked.
- `near full`: 17 snapped cards plus one free card over an occupied slot, so Pop's 19-card
  ceiling is two steps away.
- `summaries under two prompts`: three stacked cards whose sidecar holds two summaries of their
  current text, one written under the current `Summary.prompt` and one under another prompt. The
  `ok` line prints how many the sidecar held, how many were under another prompt, and how many the
  load kept. Before the search, the check compares each starting desk with its own sidecar: the
  load must keep exactly the text summaries the current prompt wrote.
- `a Spread set, one card out`: Clarity on, a Spread set gathered into the stack except one card
  popped by hand to slot 12 while it still remembers slot 7, and one card remembering slot 6, which
  another card holds. The sidecar's set also names a card that isn't there, a second entry for one
  card and a slot past the grid, and the load must drop exactly those.

From each desk it applies every command in its list to every reachable desk, breadth-first, up to
the depth (default 3), and skips desks it has already seen. The commands are New, Pop, both flips,
typing on the blank page (and an empty note), Clarity on and off, forgetting failed summaries, Return to stack for
the first two and the last desktop card, the stack arranger's moves (the shown card, or the
bottom one while the blank page shows, to the top, the middle, the bottom and past both ends; the
top card to the bottom) and its row clicks on the top and bottom card, drags of the stack and the first desktop card (onto each
other's slot, the first free slot, slot 12, a free point and one past the right edge, and their
own place), and, for each named card: delete, edit, refresh, a current summary,
a stale summary and a failed one. It also tries folder rescans (unchanged, the shown card's file
gone, a file edited, a file added), and a delete, a Return to stack, an arranger move and an arranger row
click for an id that does not exist, and the last two for a card on the desktop. Last come three
cards from an AI tool (`add_card`): Top while the user types in the stacked card, Top, and Bottom,
then the stack ribbon's Spread with four sets of ticked cells (the factory cells, cells that include
the stack's home, no cells, and three bottom-right cells that the near-full desk has room for one
of), and fresh, with the factory cells and with none.

After every step it checks:

| Property | In one sentence | The harm if it breaks |
| --- | --- | --- |
| P1 conservation | Every card stays in exactly one place, keeps its text, and only New, typing on the blank page, a card from an AI tool (exactly one, with the text it was given), Spread (at most one blank card per ticked cell), delete or a rescan add or remove a card | The next save moves a live card's file to the Trash, or writes one card's text over another |
| P2 places | No two snapped items share a slot, at most 19 cards are on the desktop, and the stack's page exists | Windows on top of each other; Pop past the ceiling; a crash on a bad index |
| P3 stack page | The stack keeps showing the same page unless the command is meant to change it (a flip moves one page around the loop; Return to stack shows the returned card; an arranger row click shows its card; an arranger move keeps the same card, or the blank page, showing; typing on the blank page shows the new card with a new blank page after it; New on a full desktop shows the blank page; a card from an AI tool with Top shows it, unless the user is typing in the stacked card, and then, like Bottom, the page stays; a card that leaves is replaced by the next surviving card under it) | Typing lands in a card the user is not looking at |
| P4 stack order | Stacked cards keep their order, except the one card an arranger move puts at its clamped index with every other card in its old order; Return to stack puts its card on top; a card from an AI tool joins at the top with Top; other cards that enter, Gather's included, join at the bottom; a move and a card from an AI tool touch nothing on the desktop | The stack reshuffles itself, an arranger move drops or misplaces a card, or a card from an AI tool lands on the desktop |
| P5 save and reload | The notes written as Markdown and the sidecar as JSON, read back the way `Library.load` reads them, give the same places, stack, Clarity and text summaries (a summary round-trips only under the prompt that wrote it: the sidecar stamps `Summary.prompt`, and a load drops any other) | A relaunch loses positions or text |
| P6 clarity | Every card's face, popped and stacked, shows collapsed exactly when Clarity is on, and the ribbon's button shows the same; `setClarity` sets it, New, writing the blank page and a Spread that makes cards turn it off, and nothing else moves it, so a card from an AI tool, a rescan, Gather or putting set cards back follows Clarity | A card is collapsed or expanded against the ribbon, or New opens a card among hidden ones |
| P7 summaries | A summary attaches only to the version of the card it describes | A card shows a summary of text it no longer has |
| P8 spread | With a card of the set on the desktop, Spread gathers exactly those cards to the bottom of the stack in reading order of their places, each remembering its place. Otherwise it lays the set out: on unchanged cells each card goes back to exactly its place, on changed cells the card in the first old place gets the first cell and so on, cards past the last cell leave the set and cells past the last card get new blank cards, and fresh first sends the old set's desktop cards to the bottom as ordinary cards. Each comes out exactly when Pop's rule finds its cell untaken, set cards before new ones, and the first new card is the one returned to focus. A click that puts nothing out changes nothing, the fresh sweep included. Return to stack makes a set card remember its place, a delete or a rescan takes a card out of the set, and nothing else changes the set. The set holds only cards on the desk, and the ribbon's button says Gather exactly when one of them is out | Spread drops a card on a taken cell, forgets where a card was, or brings back a deleted card's place; a refused click half-happens; the button gathers when it says Spread |

## Run it

From the repo root:

```bash
.claude/skills/check-desk-invariants/run.sh
```

About 10 seconds. It prints one `ok` line per starting desk and `PASS P1–P8, depth 3, …`, exit 0.
Use `run.sh 4` for depth 4 before merging a large change to `Desk.swift` (about four million
steps, most of them on the 20-card near-full desk and the Spread desk; 220 seconds on 2026-10-29
while two test builds shared the Mac).

Last synced with the code of the change that added Spread (2026-10-29). Find its commit with
`git log -S"case spread(SpreadCells" -- Cards/Desk.swift`. Depth 3 and depth 4 passed, and 40 of 40
mutants were caught. Covered code read for that sync: `Desk.swift`, `Grid.swift`, `Note.swift`,
`Library.load` (how P5 reads back), `DeskController.send`, the only caller of `Desk.apply`,
`DeskController.spread`, the only sender of `.spread`, and `StackWindow.swift` and `App.swift`, the
only callers of that. The next sync diffs those from that commit.

A failure prints the property, the starting desk and the shortest command sequence that breaks
it, then exits 1:

```
FAIL P1 conservation
  starting desk: empty
  1. .new
  2. returnToStack(CardID(rawValue: "2023-11-14 161320"))
  cards lost: ["2023-11-14 161320"], cards appeared: []
```

Read it as clicks: "New, then Return to stack on the new card, and the card is gone". The id is the
timestamp a card made by the check gets (the check's clock is fixed at 2023-11-14 22:13:20 UTC,
written in local time).

## Telling a real bug from a check that is wrong

1. Replay the sequence in a unit test in `CardsTests/DeskTests.swift`, using the same starting
   desk and commands, and assert what the property says. If the test fails, it is a real bug.
2. If the test shows the behavior is what `CARDS-SPEC.md` asks for, the property is out of date.
   Fix the property in `check/main.swift` to match the spec, and say what you changed and why in
   your report. Never weaken a property just to get a pass.
3. If the sequence cannot happen in the app (for example, a command the UI never sends in that
   state), say so, and narrow `commands()` with a comment pointing at the UI code that rules it out.

Report a real bug as a finding with the sequence in the app's words. Do not change product code
unless the user asked for a fix.

## When the code changes

- `run.sh` prints a note when `Desk.swift`, `Grid.swift` or `Note.swift` differ from the
  versions last marked reviewed (`reviewed.sha256`). Read the diff and ask:
  - A new `Command` case? The check will not compile until `checkStep` handles it under P1. Add
    the case there and add it to `commands()`.
  - A new field on `Desk`, `Card` or `SavedDesk`? Add it to `key()` (or desks that differ only in
    it are merged) and, if it is saved, to `layout()` in P5.
  - A changed rule? Update the property that states it, in the spec's words.
  - Then run `run.sh`, then `run.sh --mutants`, and only then `run.sh --reviewed`.
  - CI runs `run.sh --require-reviewed` and fails until `reviewed.sha256` is recorded again, so
    commit it with the change.
- `run.sh --mutants` breaks `Desk.swift` forty known ways in a scratch copy under
  `build/desk-check/` (never the real file) and needs every property to catch its break. If a
  mutant's text no longer exists in `Desk.swift`, update that line in `MUTANTS` in `run.sh` to an
  equivalent break of the new code. If a mutant is not caught, the check has lost its teeth: fix
  the check before trusting a pass.
- Each clause a property row in the table claims needs a `MUTANTS` entry in `run.sh` that breaks
  only that clause. A clause with no caught mutant goes under "What a pass does not cover" until it
  gets one.

## What a pass does not cover

- Only sequences of at most 3 commands (4 with `run.sh 4`) from the six starting desks, using the
  command list above. Long histories, other card counts and other drop points are not explored.
  Drags use a few fixed targets, not every point on the screen.
- Only the pure model. Windows (`DeskController.render`), the disk (`Library.save`, its failures
  and the Trash), the summarizer's timing, Hide all's `Visibility`, the swipe rules and the editor
  are outside it. Use the `verify-cards` skill for those.
- P5 checks that the sidecar the desk writes reads back. It does not check old or hand-edited
  sidecars.
- Note text is short plain text. The Markdown round trip of bold, italic and lists is
  `NoteTests.swift`'s job.
