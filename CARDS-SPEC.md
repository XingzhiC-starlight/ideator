# Ideator — prototype spec (agreed 2026-10-21, revised 2026-10-26)

Personal-use macOS prototype. Native Swift app built with Xcode.

## Windows and layering
- Each card is a real macOS window on the normal window layer (not always-on-top, not desktop-pinned).
- Cards behave as one group: clicking any card brings all cards forward; clicking another app drops them all behind it.
- Clicking a card activates the app and takes keyboard focus. Return to other apps the normal way (click or ⌘-Tab).
- Cards follow the user across Spaces and over full-screen apps.
- App home: menu bar icon with Show all / Hide all / Open stack / Settings… / Check for Updates… / Quit, and a Hide all / Show all button in the stack's ribbon (revised 2026-10-26). Global shortcut ⌃⌥I hides/shows every card (revised 2026-10-24; first ⌃⌥Space, which is macOS's Select next source in Input menu on Macs with several input sources).

## First launch (new 2026-10-24)
- The first launch on a Mac shows one card, "Welcome to Ideator", before Ideator reads or creates the notes folder, so macOS's Documents prompt comes after it. The card has a version, `WelcomeCopy.version`, raised whenever its paragraphs about Anthropic or GitHub change what they say Ideator sends or asks (revised 2026-10-27). Ideator's saved preferences record the version last acknowledged (`WelcomeSeen`; the Boolean `true` that earlier builds wrote counts as 1), and the card shows while that is below the current one. So the first launch shows it, and so does an update that says something new about what leaves the Mac, once, before the updater or a summary request does anything the older card did not announce.
- It is a card-look window as wide as the stack, top-right where the stack will appear, as tall as its text. The app icon and title come first, then five paragraphs and a Continue button (Return does the same):
  - Find it in the menu bar: no Dock icon, the stacked-rectangles icon at the top right, and that the notch can hide it, in which case the ⋯ button on the stack's ribbon has Settings and Quit too.
  - Hide and show your cards: the current shortcut by name and that Settings changes it. If the shortcut could not be registered, it says so and that there is none yet.
  - Your notes are files: Markdown files in ~/Documents/Ideator, and that macOS asks about the Documents folder after Continue.
  - Summaries are optional (revised 2026-10-27): they need the user's own Anthropic API key; Ideator then sends a card's text to Anthropic whenever the card has no summary for its text as it is now, such as when the key is saved or the card changes; only a card's text goes to Anthropic.
  - Updates come from GitHub (new 2026-10-26): once a day Ideator asks GitHub whether a newer version exists, and asks before it installs one; the daily check can be turned off in Settings; nothing else leaves the Mac.
- Continue closes the card, then opens the notes folder and the stack, starts the update check (see Updates), then records the card's version as acknowledged. A launch that ends before that (quit during the card, killed in the Documents prompt) shows it again. Quitting during the card creates nothing.
- While it is up, the global shortcut, Show all / Hide all / Open stack in the menu bar icon's menu, and opening the app again bring it forward. Settings… and Quit work as usual.
- A scratch run (`-CardsFolder`) shows it only when the environment holds `CARDS_SHOW_WELCOME=1`, and Continue then records nothing. `CARDS_SHOW_WELCOME=1` also shows it again on a normal launch.
- If the user answered Don't Allow to the Documents prompt, the "Ideator can't save your notes" alert, shown at the first failed save, also says to turn Ideator on in System Settings › Privacy & Security › Files & Folders.

## Hide all (revised 2026-10-22)
- Hide all (menu bar icon, the stack ribbon's button, or the global shortcut) hides every popped card, free ones included, and shrinks the stack to just its tan ribbon, at the top of wherever the stack is. The ribbon never hides.
- The ribbon's button is a one-click toggle, the same as the global shortcut: the icon shows the current state, a plain eye (tooltip "Hide all") while cards are shown, an eye with a slash ("Show all") while they are hidden (revised 2026-10-22). It sits left of the menu button.
- While hidden, the ribbon keeps New, Clarity, the toggle and the menu button, plus the count badge, which moves into the ribbon beside the toggle because the card area is gone (on a very narrow stack the badge is dropped before it would cover the toolbar). The ribbon can still be dragged. There is no Pop while hidden: its button is on the stacked card, which is gone too (revised 2026-10-22).
- Show all (the toggle or the menu bar icon), the global shortcut, or opening the app again (Spotlight, Finder, Launchpad) while it runs brings back the stack's card area and every popped card, and brings the app forward.
- New while hidden shows only that card; the rest stay hidden. Its slot is chosen as if the hidden cards were in place, free ones included (revised 2026-10-22: Pop is no longer here).
- Hidden is not persisted: every launch starts with everything shown.

## Grid and sizing
- Screen is an invisible 5 × 4 grid. Card width = screen width / 5; height = (screen height below menu bar) / 4.
- 20 equal slots. The stack takes one (top-right by default, so Pop still fills from the top-left; revised 2026-10-22), so at most 19 cards are on the desktop. Any saved place of the stack is kept; a sidecar older than version 2 is read as none (revised 2026-10-27).
- Recomputed when the display setup changes; snapped cards re-snap to their slots, free cards and a free stack keep their place as a fraction of the screen (revised 2026-10-22).

## Stack
- Its own card-sized window, top-right until you move it (revised 2026-10-22): the control center, marked by a tan ribbon on top.
- Moved like a card (see Moving cards and the stack), by pressing the ribbon's empty space and dragging. A click there that does not move still acts as the edge band under it.
- Looks like one card: the ribbon holds the toolbar, "Desktop full" when it applies, the Hide all / Show all toggle and the menu button; below it, the selected stacked card (header and body). No list or divider for the cards underneath. The count badge sits in the bottom-right corner of the card area, clear of the card's hover buttons and its formatting bar (revised 2026-10-22).
- Toolbar: New, Clarity on/off (global). Clarity always reads "Clarity" and shows its state by text color alone: soft brown when off, the accent color when on. Its tooltip and accessibility value also say on or off (revised 2026-10-22). To its right come "Desktop full" (it truncates before any button moves), the Hide all / Show all toggle (see Hide all) and a menu button with Settings… / Quit, so the control center works even when the menu bar icon is hidden (revised 2026-10-22).
- The selected stacked card is a full card (revised 2026-10-22): edited in place exactly like a popped card (see Card content and editing), with every per-card button a popped card has, and ↗ Pop where a popped card has ↩ Stack (Pop moved here from the ribbon, revised 2026-10-22), and collapsible to its summary (see Clarity mode).
- Deleting the selected card shows the one underneath.
- At launch the stack shows its top card, or the blank page when the stack is empty.
- The count badge counts real cards only, never the blank page.
- The count badge is a button: it opens the stack arranger (see Arranging the stack). Its tooltip reads "Arrange the stack" (revised 2026-10-23).

## Pop / return / find space
- Pop, the ↗ Pop button on the stacked card (revised 2026-10-22), takes the first grid slot (left→right, top→bottom) not taken by a card or the stack. A snapped card or stack takes its slot; a free one takes the slot it covers most. Other apps' windows are ignored.
- No slot left, or 19 cards already on the desktop → Pop refuses and the stack shows "Desktop full". The ↗ Pop button is greyed and its tooltip reads "Desktop full" (revised 2026-10-22).
- There is no Pop on the blank page, which has no per-card buttons, nor while Hide all has removed the card area (revised 2026-10-22).
- Popping the card being edited on the stack moves the cursor with it; the stack then shows the next card.
- "↩ Stack" button returns a card to the top of the stack. It forgets where the card was; a later Pop takes the first free slot.

## Moving cards and the stack (new 2026-10-22)
- Drag a card, expanded or collapsed, by its header or by the margin around its text, or the stack by its ribbon's empty space (revised 2026-10-27).
- While dragging, a guide outlines the slot nearest the dragged card's center: faint and dashed while a drop would stay free, solid and filled in once a drop would snap.
- On release it snaps to that slot if its center is within 15% of a cell (in cell widths and heights) of the slot's center. Otherwise it stays exactly where it was dropped.
- Snapping onto a slot held by another snapped card or the stack swaps them: the occupant goes to the dragged one's old place, a slot or an exact free spot. Free cards that only overlap the slot stay put.
- Free cards overlap anything. The card being dragged comes to the front; clicking the app keeps the cards' front-to-back order.
- Free places may overhang the screen (revised 2026-10-22): a card or the stack can hang partly off the left, right and bottom edges, but never above the top, so its header (the ribbon, for the stack) stays under the menu bar. At least 40pt of it stays reachable: its top 40pt, the header strip, and 40pt of its width stay inside the screen minus the Dock. A drop past that limit lands at the limit, and the guide follows the limit too.
- Snapped places are always fully on screen; only free places overhang.
- When the display setup changes, the limit is applied to the new screen so a card is never lost off a smaller one, but its saved spot is kept as it was and comes back out on a larger one.
- Free positions are saved, so they survive relaunch.

## Switching stacked cards (stack only; revised 2026-10-22)
- Purpose: show the cards hidden under the stack.
- The stack is a loop. Next shows the card under the selected one, and previous the card above it. Flipping never changes the stack's order (revised 2026-10-27).
- The loop always holds one blank page, after the last card and before the first.
- Two-finger horizontal swipe on the stack: one card per swipe, next or previous following the system scroll direction. Vertical scroll scrolls the selected card's text.
- Edge bands stay as a click alternative: an invisible band = 5% of the stack's width/height along all four edges. Right/bottom = next, left/top = previous. On hover the band tints faintly and shows ‹ or ›. Popped cards have no bands.
- Because of the blank page, swiping and the bands work with any number of stacked cards, including zero or one.
- ↗ Pop takes the selected card.

## Arranging the stack (new 2026-10-23)
- Purpose: put the stacked cards in the order you want, the only way besides cards entering or leaving that the stack's order changes.
- Opening: click the count badge, wherever it sits (the card's corner, or the ribbon under Hide all). With zero stacked cards the badge does nothing. When a narrow ribbon has dropped the badge, there is no arranger until the card area is back.
- A popover anchored to the badge, one row per stacked card, top of the stack first. The blank page and popped cards are not listed. Each row shows the card's header ("Untitled" when empty), truncated with "…". It grows to about 10 rows, then scrolls.
- The card the stack shows is highlighted, and the stack keeps showing that same card after any move.
- Clicking a row's name shows that card on the stack; under Hide all this also brings back the stack's card area, and nothing else, so the card can be seen (moving cards brings back nothing). The popover stays open until Esc or a click outside it.
- Moving by mouse: each row has a grip (≡) on its right, and the header on its left truncates with "…" before the grip; only the grip starts a drag, with the open-hand cursor over it, and a click anywhere else on the row shows the card. A standard insertion line shows where the card will land, and the list scrolls when dragged near its top or bottom. The order changes and is saved only on drop. Esc mid-drag, or dropping outside the list, cancels.
- Moving by keyboard: the popover opens with the shown card's row selected. ↑/↓ select another row; ⌥↑/⌥↓ move the selected card one place, and it stays selected; Return or Space shows it on the stack; Esc closes (or cancels a drag first).
- VoiceOver: the badge reads "N cards in the stack, button" and can be reached with Tab when keyboard navigation is on. Each row reads "<title>, 3 of 7", plus "current card" for the one the stack shows, with the actions Move up and Move down, and press to show the card. The grip is hidden from VoiceOver. After any move VoiceOver announces the new place, such as "Moved to 2 of 7"; moving past an end does nothing and announces "Already at the top" or "Already at the bottom".
- The list follows the desk while open: popped, returned, new, deleted, renamed or rescanned cards update it in place. A drag whose card leaves the stack mid-drag is cancelled.
- Each move is saved as the stack order in the sidecar, like any other change.

## Blank page (new 2026-10-22)
- Typing its first character turns it into a real card in the same place in the loop (the bottom of the stack). The card stays selected with the cursor in it, and a new blank page appears right after it.
- Left untouched, it creates nothing.
- Always expanded, even with Clarity ON. No per-card buttons until it becomes a card.

## Card content and editing
- Applies to popped cards and to the selected stacked card alike.
- First line (first paragraph) is automatically the bold level-1 header, regardless of formatting.
- Body formatting: bold, italic, bullet list, numbered list, checkboxes, and list items nested up to three levels (see Nested lists). Nothing else (revised 2026-10-23).
- Apply via ⌘B / ⌘I; typing `- ` or `* ` (bullet), `1. ` with any number (numbered), or `[] ` or `[ ] ` (checkbox) starts lists (revised 2026-10-27); Enter continues a list, Enter on an empty top-level item ends it.
- Undo gives back text exactly, bold and italic included, also after an edit that joined a body line into the header (added 2026-10-27).
- A five-button formatting bar appears along the bottom of a card only while editing.
- Scroll wheel/trackpad scrolls whichever card the pointer is over. The card being edited has a stronger border.
- Per-card buttons (clarity toggle, summary refresh, ↩ Stack, trash) fade in on hover only. Trash asks "Delete this card?". The stacked card has every one of them, with ↗ Pop where a popped card has ↩ Stack (revised 2026-10-22).
- Hover is where the pointer is, also when a card appears or moves under a pointer that rests (Show all, Pop, a snap). While the buttons are hidden a click there is a click on the card under them, never on a button. VoiceOver still lists and presses them (added 2026-10-27).
- A long title wraps, or truncates on a collapsed card, before the buttons, whether they show or not (added 2026-10-27).
- New: creates a blank card and pops it straight out, cursor on the header line, always expanded. Desktop full → New shows the stack's blank page instead.

## Nested lists (new 2026-10-23)
- Bullet, numbered and checkbox items nest under one another, any kind under any kind, at most 3 levels deep. Only list items have levels: plain lines and the header always sit at the left edge.
- Each level indents 20pt further. Bullets are `•`, `◦`, `▪` by level; numbers and checkboxes look the same at every level.
- A nested numbered run restarts at 1 under its parent, and the parent's count continues past its children. Every level uses `1.` style.
- Tab moves the item (or every selected item) one level deeper, Shift-Tab one level up, each carrying all of its children. Tab does nothing if any part would pass level 3, or if the item has no list item above it at the same level or deeper to sit under, so a level is never skipped. Shift-Tab on a top-level item turns it into plain text.
- On the header, a plain line, or the first item of a list, Tab types a tab character as before. A selection that touches a list item never turns into a tab: inside a first item, or from the header into one, Tab does nothing (revised 2026-10-27).
- Enter on an empty nested item, or Backspace at the very start of one, moves it up one level. At the top level both behave as before.
- Changing an item's kind changes only that line; ticking a parent checkbox leaves its children alone.
- After every edit, no item sits more than one level deeper than the list item above it, and an item right after a plain line is at the top level. Children left without a parent (a deleted line, a parent turned plain, undo) move up just enough to fit.
- Each Tab, Shift-Tab or paste, with any tidying it causes, is one undo step.
- In the card file each level is 4 spaces of indent. When reading, a list line indented further than the list item above it is that item's child; a tab counts as 4 spaces; depth is tidied as above. Indented plain lines stay plain with their spaces. Existing files with indented list lines therefore load nested, and are rewritten with 4-space indents on their next save.
- The summary prompt shows each level as 2 spaces of indent.

## Copy and paste (new 2026-10-23)
- Copy puts two forms on the clipboard: the card file's Markdown (markers, 4 spaces per level, `**bold**`, `*italic*`) and HTML with real nested `<ul>`/`<ol>` lists, so Notes, Mail and Docs paste a list and Markdown apps paste Markdown.
- A selection inside one line copies just its text. A selection crossing a line break copies every line it touches with its marker; levels count from the shallowest copied item, and a copied header becomes `# Title`.
- Paste reads HTML first when it holds a list (a selection in the Claude app, web pages, Notes); otherwise the plain text is read as Markdown, also accepting `•` `◦` `▪` `·` `‣` bullets and `1)` numbering (terminal output such as Claude Code's).
- From HTML: list items, nesting, ordered vs unordered, checkboxes, bold and italic are kept. Headings, links, code and table cells become plain lines with their text; images are dropped.
- A paste with no line break is inserted as typed text and never starts a list.
- Only a line break separates lines. A bare CR, U+2028, U+2029 or U+0085 inside pasted HTML, or inside a line of a file edited elsewhere, shows as a space (added 2026-10-27): the editor would otherwise split a paragraph the note does not have, and the next copy or paste crashed.
- A multi-line paste: on an empty line, the first pasted line replaces it (kind and level); inside text, the first pasted line's text joins the current line, which keeps its kind. Later lines keep their own kinds, shifted by the current item's level, and anything past level 3 is tidied up. Pasting into the header puts the first line in the header and the rest in the body.

## Clarity mode
- Collapsed card: same size and position, header stays, body replaced by the 3-line AI summary in a lighter style, cut with "…" if longer (revised 2026-10-24). Applies on the stack too.
- Stack's Clarity button is a global toggle: ON collapses every card, stacked ones included; OFF expands every card.
- Clicking a collapsed card's body expands just that card and puts the cursor in it; does not flip the global button.
- Per-card button toggles just that card.
- A card popped keeps its state, so a card popped while global is ON comes out collapsed.

## AI summaries
- Provider: Anthropic API, model Claude Haiku 5.5. API key pasted once into the app's settings, stored outside the code.
- Every card gets one, stacked or popped, under the same rules.
- Trigger (revised 2026-10-27): a summary is requested for every card with two or more non-blank body lines, stacked or popped, collapsed or not, that has no summary for its text as it is now. That is a few seconds after typing stops; when the per-card refresh button is pressed; at once for a file changed or added outside the app (found when Ideator becomes active); for every such card when a key is saved; at every launch for any card with no saved summary or whose file changed while Ideator was closed (its saved summary is then for the older text); and once for every card after a build whose prompt changed (revised 2026-10-24). A summary is cached with the card in the sidecar and a failure never is, so a relaunch asks again; so does every launch while nothing can be saved, as under a newer sidecar. A launch that cannot list the folder opens empty and sends nothing; the sends come later in that run, at the first rescan that can list the folder, which takes in each card not yet on the desk as new and so requests a summary for each, even one whose file is unchanged and whose untouched sidecar holds a matching summary. A new or removed API key retries every failed summary, and a request still waiting or in flight under the old key is cancelled and sent again at once under the new one (revised 2026-10-27). PRIVACY.md tells the user the same.
- No summary for empty or one-line bodies.
- Prompt (revised 2026-10-24): header + body in → one paragraph of at most ~120 characters (about 20 words; about 60 characters for Chinese, Japanese or Korean), no line breaks, no preamble, same language as the card (the kind label too, e.g. 待办清单 for a Chinese to-do list).
  - It reminds the user what the card is: kind and topic first, then the gist if there is room. "To-do list for the Tokyo trip: flights, hotel, charger." "Thoughts on why the drag felt slow, leaning toward input focus."
  - The model names the kind itself, guided by examples (to-do list, thoughts, plan, meeting notes, draft, question, links, ideas). A card with no clear kind is "Notes on <topic>".
  - The header is already shown above the summary, so the summary never restates it.
  - To-do lists name only the unchecked items and the count done ("2 of 5 done: hotel, charger, visa"), or say all done.
  - A thin card gets a short summary: infer its intent, never invent details to fill the space.
  - The reply is the summary alone: it never explains itself or comments on the title or the prompt.
- While generating: small spinner in the summary area. On failure: "Summary unavailable", hover shows the reason.

## Settings (new 2026-10-24)
- Settings… (the menu bar icon, or the stack ribbon's ⋯ menu) opens one window. It is as tall as its rows need.
- Shortcut: a button that shows the global shortcut, ⌃⌥I by default (revised 2026-10-24: ⌃⌥Space is macOS's Select next source in Input menu on Macs with several input sources). Click it, then press the new keys. While it records it shows the modifiers held and has released the current shortcut, so pressing that one is recorded instead of hiding the cards. Esc, a click, or leaving the window cancels.
- A shortcut needs ⌘ or ⌃ plus at least one more modifier, so typing never triggers it. A refused combination is named ("⌘K can't be the shortcut. …") and the button keeps recording.
- A combination macOS refuses to register is refused with the reason, and the old shortcut stays. "Use Default" goes back to ⌃⌥I and is dimmed while that is in use. The choice survives a relaunch. Settings reads the shortcut line and the key status again each time the window comes forward (revised 2026-10-24).
- If the saved shortcut cannot be registered, the line under the button says why and that there is no shortcut until another is chosen. If macOS has its own shortcut on the combination (⌃⌥Space, for Select next source in Input menu), the line says so; Ideator still registers it.
- API key: a secure field, a line that says whether a key is saved, and Save and Remove Key. When the Keychain refuses either one (added 2026-10-27), it beeps, the line still says whether a key is saved, and the summarizer is not told the key changed.
- A scratch run (`-CardsFolder`) reads the default shortcut, saves nothing of Settings' shortcut, and does not register the global shortcut until one is chosen in Settings.
- A scratch run never reads or writes the login Keychain (revised 2026-10-26): it starts with no key whatever the owner has saved. A key saved in Settings works for that run only, and the status line then says "A key is held for this run only. Paste a new one to replace it."
- Updates (new 2026-10-26): a "Check for updates automatically" checkbox, which is Sparkle's own setting (Ideator keeps no copy), and a Check Now button on the same row. Under them a caption gives the version line, then whether this run checks: "Ideator asks before it installs an update.", "A scratch run (-CardsFolder) doesn't check for updates." or "Only builds made by scripts/package.sh check for updates." In a build or run that never checks, both controls are dimmed. While the welcome card is up the checkbox works and Check Now is dimmed, so the daily check can be turned off before the first one.
- Privacy (revised 2026-10-27): the last rows, a heading and one line: "With a key saved, Ideator sends a card's text to Anthropic, using your own key, to write its summary, whenever the card has no summary for its text as it is now. It does so, for example, after you change a card, when you save a key, at launch after a failed try, and after an update that changes how Ideator asks for summaries. The key stays in your login Keychain. Once a day, and whenever you click Check Now, Ideator asks GitHub whether a newer version exists. GitHub sees your IP address and which version you have. Nothing else leaves your Mac: no analytics, no crash reports." PRIVACY.md says the same in full.
- Version line (new 2026-10-25, revised 2026-10-26): the start of the caption under the Updates rows, in the same small type, names the build. `Version 0.9 (57), commit 1a2b3c4` is a build `scripts/package.sh` made from a clean tree, and `Version 0.9 (57), commit 1a2b3c4 with local changes` one made from a tree with changes, untracked files included. `Version 0.9 (1), a development build` is any build without a valid stamp, such as a run from Xcode. A valid stamp is a 40-digit lowercase hex commit and a tree state of exactly YES or NO, so a tree state of "unknown" never reads as clean. A scratch run shows the same line.

## Updates (new 2026-10-26)
- Ideator uses Sparkle to look for a newer build on GitHub Releases. The feed is `https://github.com/XingzhiC-starlight/ideator/releases/latest/download/appcast.xml`, set in the signed Info.plist. A `SUFeedURL` default or launch argument does not change it.
- The check runs once a day and is on by default, without Sparkle's permission prompt, because the welcome card announced it. Settings' checkbox turns it off.
- Check for Updates… sits after Settings… in the menu bar icon's menu. The stack ribbon's ⋯ menu stays Settings… and Quit; Settings' Check Now does the same for a Mac whose notch hides the icon. Both are dimmed until the updater starts, while Sparkle downloads in the background, and in a build or run that never checks.
- First run: no request goes to GitHub before Continue. The updater starts right after the notes folder opens, after the Documents prompt, and with no check on record it checks at once. Quitting during the welcome sends nothing. The same holds on the first launch after an update that raised the welcome card's version (added 2026-10-27): the card shows first, and the updater starts only after Continue.
- A newer build opens Sparkle's window with the release notes and Skip This Version, Remind Me Later and Install Update. It names both builds, "0.9 (58)" and "you have 0.9 (57)", since every build is 0.9 for now. Nothing installs until the user clicks Install Update.
- An update found right after launch opens in front. One found later opens behind other apps, and until the user looks at it, installs, skips or dismisses it, the menu bar item reads "Update to 0.9 (58)…".
- An installed build whose number is equal to or above the newest release is up to date.
- Never checks: a build `scripts/package.sh` did not stamp (from Xcode, build number 1), and a scratch run (`-CardsFolder`), which creates no Sparkle object and writes no `SU*` key to the owner's preferences. The one exception is an update-test copy, whose plist has `IdeatorUpdateTest` = YES and a bundle id of its own: it checks in a scratch run, and may use a plain-http feed on localhost or 127.0.0.1.
- Sparkle requires a signed feed and checks the dmg's EdDSA signature before it opens the dmg. It sends no system profile.

## Storage
- One Markdown (.md) file per card in ~/Documents/Ideator/.
- A card file reads the way CommonMark reads it (added 2026-10-27): a backslash escapes only punctuation, so `C:\Users\me` keeps its backslashes, and asterisks style text only when they hug it (`*word*`), so `rm *.txt *.log` and `2 * 3 * 4` keep theirs. A file edited outside Ideator shows what it says, and saving it changes none of its text. Files Ideator wrote read back to the same bytes.
- One hidden sidecar file for positions (each card's and the stack's slot or free spot), stack order, collapsed state, and cached summaries.
- The sidecar carries a format version. A sidecar written by a newer Ideator is never overwritten: cards open and card files save as usual, places, Clarity and summaries are not saved, and a notice at launch says to update (added 2026-10-24).
- That check runs again before every sidecar write, not only at launch (added 2026-10-27): the other Mac can arrange the folder while this one runs. The notice shows once per run, when the check first finds the newer file.
- A folder that can't be listed at launch (macOS refused, a volume not mounted) opens empty with the notice "Ideator couldn't read your notes" (added 2026-10-27). That run never writes the sidecar, so the arrangement it never read survives. Cards written meanwhile save when the folder allows it, a rescan brings the folder's cards into the stack, and the next launch arranges everything from the sidecar.
- A failed save is never silent (revised 2026-10-27): the first one shows "Ideator can't save your notes" (see First launch for the Documents case), and quitting while a save still fails asks "Quit without saving?" with Cancel and Quit Anyway, instead of dropping the changes that alert promised to keep.
- A scratch run keeps its notes in the folder named by the `-CardsFolder <folder>` launch argument (added 2026-10-27). Only the argument counts: a `CardsFolder` default in Ideator's preferences changes nothing. An update-test copy (see Updates) also reads its own `CardsFolder` default, because Sparkle relaunches an app without its arguments.

## Look
- Warm beige frosted-glass cards (revised 2026-10-22, see DESIGN.md), thin border, soft shadow, system font. Per-card colors later.

## Explicitly out of scope for the prototype
- Always-on-top mode, drag-to-stack, fonts/colors/sizes/tables/images/links, multiple stacks, sync, sharing.
