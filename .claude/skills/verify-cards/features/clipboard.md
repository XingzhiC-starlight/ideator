# Copy and paste

A user copies lines from a card and gets the card file's Markdown plus an HTML nested list on the
clipboard, so Notes, Mail and Docs paste a real list and Markdown apps paste Markdown. Pasting
reads an HTML list first (the Claude app, web pages, Notes, Google Docs), otherwise the plain text
as Markdown that also accepts `•◦▪·‣` bullets and `1)` numbers from a terminal. One pasted line is
typed text; several lines keep their kinds and levels, and one ⌘Z takes the whole paste back.

## Sub-features

- `clip-copy-lines` A selection across lines copies every touched line with its marker, levels
  counted from the shallowest copied item, as Markdown and HTML.
- `clip-copy-text` A selection inside one line copies only its text, and no HTML.
- `clip-paste-html` An HTML list pastes as nested items with kinds, checkboxes, bold and italic.
- `clip-paste-terminal` Text with `•◦▪` bullets and `1)` numbers pastes as nested items.
- `clip-paste-one-line` One pasted line is typed text and never starts a list.
- `clip-paste-header` Several lines pasted into the header: the first joins it, the rest are body.
- `clip-paste-undo` One ⌘Z removes a whole paste; ⇧⌘Z puts it back.

## How to get to it (user POV)

- ⌘C, ⌘X and ⌘V in any card (the hidden Edit menu); dragging text out of or into a card.
- Copying from another app (the Claude app, a browser, Notes, a terminal) and pasting in a card.

## Driving it with cards-verify

Preconditions:

- `cv launch`; `cv doctor` prints `healthy`; a card with a nested list exists (see
  [nested-lists.md](./nested-lists.md), for example the `Plan` card).
- **`cv clip save` before the first `clip set` or ⌘C, and `cv clip restore` after the last
  paste.** The clipboard is the owner's. `clip set` refuses until it is saved, and `cv stop`
  restores it if you forget. To prove the restore, compare
  `osascript -e 'clipboard info' | shasum` and `pbpaste | shasum` before and after: both must
  match, since the restore writes every type back in its saved order. Never print the owner's
  clipboard.

- **Copy lines.** In `Plan`, `cv ax key cmd+up`, `cv ax key down`, `cv ax key cmd+left`, then
  `cv ax key shift+down` three times (Day one through hotel). `cv ax key cmd+c`, then
  `cv clip show` lists `public.html` and `public.utf8-plain-text` among its types (with their
  older aliases, `Apple HTML pasteboard type` and `NSStringPboardType`), then the Markdown
  `1. Day one` / `    1. flight` / `    2. hotel` and the HTML
  `<meta charset="utf-8"><ol><li>Day one<ol><li>flight</li><li>hotel</li></ol></li></ol>`.
- **Levels from the shallowest.** Select only flight (`cv ax key cmd+up`, `cv ax key down` twice,
  `cv ax key cmd+left`, one `shift+down`) and copy: the Markdown is `1. flight`, at the top level,
  and the HTML `<meta charset="utf-8"><ol><li>flight</li></ol>`.
- **Copy text.** The same keys to the start of flight, then `cv ax key shift+cmd+right`,
  `cv ax key cmd+c`. `cv clip show` lists no `public.html`, and the text is `flight`.
- **Paste HTML.** Put the caret on an empty plain line after the list: `cv ax key cmd+down`, then
  `cv ax key return` twice (the first makes an empty `3.` item, the second ends the list).
  `cv clip set $'Set up the repo\nclone it' '<ol><li><strong>Set up</strong> the repo<ul><li>clone it</li></ul></li></ol>'`
  (the Claude app's shape) and `cv ax key cmd+v`. After 1.5 s, `cv files` shows
  `3. **Set up** the repo`, `    - clone it` under `2. Day two`: the pasted item continues the
  numbered list above it, as typed items do.
- **Undo the paste.** `cv ax key cmd+z`: `cv files` shows nothing pasted and the line empty again,
  as an empty `3. ` item (the empty last line takes the shape of the line above; see the
  nested-lists gotchas). `cv ax key shift+cmd+z` brings the paste back.
- **Paste terminal text.** `cv ax press New`, `cv ax type 'Terminal\n'`, then
  `cv clip set "$(printf '⏺ Done:\n\n  • Note.swift\n    ◦ tidyLevels\n      ▪ one scan\n  • Clipboard.swift\n  1) tests\n  2) the app')"`
  and `cv ax key cmd+v`. The file shows `⏺ Done:` as plain text, `- Note.swift`,
  `    - tidyLevels`, `        - one scan`, `- Clipboard.swift`, `1. tests`, `2. the app`.
- **One line.** `cv clip set '- not a list'`, caret at the end of a line, `cv ax key cmd+v`: the
  text joins the line and the file has no new item.
- **Into the header.** `cv ax key cmd+up`, `cv ax key cmd+right`, then
  `cv clip set $'s from the clipboard\n- first\n    - second'` and `cv ax key cmd+v`. The file's
  title line gains the first line; `- first` and `    - second` start the body.
- **Restore.** `cv clip restore`, then compare the clipboard fingerprints from before.

## Gotchas

- ⌘C and ⌘V need Ideator to be the active app; `cv ax key cmd+…` activates it first.
- `"$(cat file)"` drops the file's last newline, which a paste drops anyway (one trailing line
  break is ignored).
- Dragging text in or out of a card goes through the same copy and paste code, but cards-verify
  cannot drag text, so it is not driven here.
- See the selection gotcha in [nested-lists.md](./nested-lists.md): `shift+down` from a deeper item
  can land inside the next line's text and copy it too.
