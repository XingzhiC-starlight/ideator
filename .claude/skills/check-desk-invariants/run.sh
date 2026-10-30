#!/bin/bash
# Bounded exhaustive check of the real Desk rules. See SKILL.md.
#
#   run.sh [DEPTH]        build against the current Cards/*.swift and check (default depth 3, ~10 s)
#   run.sh --mutants      break the code every way in MUTANTS; each must be caught by its property
#   run.sh --reviewed     record the current Desk/Grid/Note sources as reviewed against the properties
#   run.sh --require-reviewed   fail while those sources differ from the reviewed ones (CI runs this)
#   run.sh --inputs-key   print a hash of everything the search and the mutants read (CI skips them on a pass of it)
set -euo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SKILL/../../.." && pwd)"
OUT="$REPO/build/desk-check"
SOURCES=(Desk.swift Grid.swift Note.swift)
REVIEWED="$SKILL/reviewed.sha256"

build() {  # build DIR BINARY: compile the three model files from DIR with the checker
  local dir="$1" bin="$2" out status=0
  mkdir -p "$(dirname "$bin")"
  out="$(swiftc -O "${SOURCES[@]/#/$dir/}" "$SKILL/check/main.swift" -o "$bin" 2>&1)" || status=$?
  grep -E "error|warning: (var|imm)" <<< "$out" || true
  ((status == 0)) || { echo "desk-check: did not compile" >&2; exit 2; }
}

fingerprint() { (cd "$REPO/Cards" && shasum -a 256 "${SOURCES[@]}"); }

inputs_key() {  # the model sources, the checker, this script (its MUTANTS) and the compiler
  { fingerprint; (cd "$SKILL" && shasum -a 256 check/main.swift run.sh); swiftc --version 2>&1; } | shasum -a 256 | cut -d' ' -f1
}

staleness() {
  if [[ ! -f "$REVIEWED" ]] || ! diff -q <(fingerprint) "$REVIEWED" >/dev/null; then
    echo "note: Cards/{Desk,Grid,Note}.swift changed since the properties were last reviewed."
    echo "      Read the diff against SKILL.md's 'When the code changes', then run: run.sh --reviewed"
  fi
}

# Each mutant: property it must break | exact text in the file | replacement | the file under Cards/
# (Desk.swift when the column is left out). A "\n" in a text stands for a line break.
MUTANTS=(
  "P1 conservation|insertCard(removePopped(at: i), at: 0)|_ = removePopped(at: i)"
  "P2 places|            setPlace(of: occupant, to: from)|            _ = occupant"
  "P2 places|count < Slot.count - 1 && !taken.contains(cell)|!taken.contains(cell)"
  "P3 stack page|if i <= selection { selection += 1 }|"
  "P4 stack order|insertCard(Card(id: id, note: note), at: stack.count)|insertCard(Card(id: id, note: note), at: 0)"
  "P5 save and reload|stackFree: stackPlace.savedFree,|stackFree: nil,"
  "P6 clarity|CardFace(id: card.id, note: card.note, collapsed: clarity,|CardFace(id: card.id, note: card.note, collapsed: false,"
  "P7 summaries|update(id) { card in if summary.source == card.digest { card.summary = summary } }|update(id) { card in card.summary = summary }"
  "P3 stack page|if let shown, let i = stack.firstIndex(where: { card in card.id == shown }) { selection = i }|"
  "P4 stack order|stack.insert(stack.remove(at: from), at: to)|stack.insert(stack.remove(at: from), at: min(to + 1, stack.count))"
  "P3 stack page|if let i = stack.firstIndex(where: { card in card.id == id }) { selection = i }|if let i = stack.firstIndex(where: { card in card.id == id }) { selection = min(i + 1, stack.count) }"
  "P5 save and reload|text: text, prompt: Summary.prompt)|text: text, prompt: summary.source)"
  "P5 save and reload|for s in saved.summaries where s.prompt == Summary.prompt {|for s in saved.summaries {"
  "P3 stack page|if !typing { selection = 0 }|"
  "P3 stack page|if !typing { selection = 0 }|selection = 0"
  "P4 stack order|insertCard(card, at: 0)|insertCard(card, at: stack.count)"
  "P4 stack order|insertCard(card, at: stack.count)|insertCard(card, at: max(stack.count - 1, 0))"
  "P3 stack page|insertCard(card, at: stack.count)|insertCard(card, at: stack.count); selection = 0"
  "P4 stack order|insertCard(card, at: stack.count)|popped.append(PoppedCard(card: card, place: .free(GridPoint(x: 0.5, y: 0.5))))"
  "P6 clarity|clarity: clarity, desktopFull: firstFreeSlot == nil,|clarity: false, desktopFull: firstFreeSlot == nil,"
  "P6 clarity|        clarity = false   // a new card opens expanded, so every card does|"
  "P6 clarity|        clarity = false\n        insertCard(Card(id: freshID(at: date), note: note), at: selection)|        insertCard(Card(id: freshID(at: date), note: note), at: selection)"
  "P6 clarity|case .setClarity(let on): clarity = on|case .setClarity: clarity.toggle()"
  "P6 clarity|let card = Card(id: freshID(at: date), note: note)\n        switch landing|clarity = false\n        let card = Card(id: freshID(at: date), note: note)\n        switch landing"
  "P5 save and reload|clarity: clarity,\n            stackSlot|clarity: false,\n            stackSlot"
  "P8 spread|insertCard(removePopped(at: i), at: stack.count)|insertCard(removePopped(at: i), at: 0)"
  "P8 spread|ka != kb ? ka < kb :|ka != kb ? ka > kb :"
  "P8 spread|guard room.admits(home.slot),|guard"
  "P8 spread|place: home)|place: .slot(home.slot))"
  "P8 spread|spreadSet = spreadSet?.removing(id)|"
  "P5 save and reload|spread: spreadSet.map { SavedSpread(\$0) }|spread: nil"
  "P6 clarity|            clarity = false   // Spread's new blank cards open expanded, as New's do|"
  "P6 clarity|popped.append(PoppedCard(card: removeCard(at: i), place: home))|clarity = false; popped.append(PoppedCard(card: removeCard(at: i), place: home))"
  "P8 spread|spreadSet?.remember(leaving.card.id, at: leaving.place)|"
  "P8 spread|guard let laid = next.layOut(cells, at: date) else { return nil }|guard let laid = next.layOut(cells, at: date) else { self = next; return nil }"
  "P8 spread|if let set = spreadSet, set.cells == cells {|if spreadSet != nil {"
  "P2 places|room.take(cell)|"
  "P8 spread|spreadButton: spreadButton)|spreadButton: .spread)"
  "P5 save and reload|where homes[m.card] == nil && notes[m.card] != nil {|where homes[m.card] == nil {"
  "P5 save and reload|where homes[m.card] == nil && notes[m.card] != nil {|where notes[m.card] != nil {"
  "P1 conservation|            if deletes {|            if false {"
  "P1 conservation|            if deletes {|            if true {"
  "P8 spread|\$0.note.isBlank|\$0.note == .blank"
  "P8 spread|return .gather(deletes: allCards.allSatisfy|return .gather(deletes: poppedCards.allSatisfy"
  "P1 conservation|for id in set.homes.keys { delete(id) }|for id in popped.map(\\.card.id).filter(set.contains) { delete(id) }"
  "P8 spread|spreadButton: spreadButton)|spreadButton: spreadButton.isOut ? .gather(deletes: false) : .spread)"
  "P6 clarity|for id in set.homes.keys { delete(id) }|for id in set.homes.keys { delete(id) }; clarity = false"
  "P1 conservation|for id in set.homes.keys { delete(id) }|for id in set.homes.keys { delete(id) }; for card in allCards where card.note.isBlank { delete(card.id) }"
  "P3 stack page|for id in set.homes.keys { delete(id) }|for id in set.homes.keys { delete(id) }; selection = 0"
  "P1 conservation|for id in set.homes.keys { delete(id) }|for id in set.homes.keys { delete(id) }; _ = layOut(cells, at: date)"
  "P8 spread|if fresh { next.dropSpreadSet() }|if fresh { if case .gather(deletes: true) = spreadButton, let set = spreadSet { for id in set.homes.keys { next.delete(id) } } else { next.dropSpreadSet() } }"
  "P8 spread|var isBlank: Bool { header.allSatisfy(\\.isWhitespace) && body.allSatisfy(\\.isBlank) }|var isBlank: Bool { body.allSatisfy(\\.isBlank) }|Note.swift"
  "P8 spread|var isBlank: Bool { header.allSatisfy(\\.isWhitespace) && body.allSatisfy(\\.isBlank) }|var isBlank: Bool { header.allSatisfy(\\.isWhitespace) }|Note.swift"
  "P8 spread|var isBlank: Bool { text.allSatisfy(\\.isWhitespace) }|var isBlank: Bool { !kind.isList && text.allSatisfy(\\.isWhitespace) }|Note.swift"
)

mutants() {
  local caught=0 n=0
  for m in "${MUTANTS[@]}"; do
    IFS='|' read -r property from to file <<< "$m"
    file="${file:-Desk.swift}"
    from="${from//\\n/$'\n'}" to="${to//\\n/$'\n'}"
    n=$((n + 1))
    local dir="$OUT/mutant-$n"
    rm -rf "$dir"; mkdir -p "$dir"
    cp "${SOURCES[@]/#/$REPO/Cards/}" "$dir/"
    if ! FROM="$from" TO="$to" perl -0 -i -pe 'BEGIN { $n = 0 } $n += s/\Q$ENV{FROM}\E/$ENV{TO}/g; END { exit($n == 1 ? 0 : 3) }' "$dir/$file"; then
      echo "mutant $n ($property): its text is no longer in $file exactly once; update MUTANTS in run.sh"
      continue
    fi
    build "$dir" "$dir/desk-check"
    local result
    result="$("$dir/desk-check" 3 || true)"
    if grep -q "^FAIL $property" <<< "$result"; then
      caught=$((caught + 1))
      echo "mutant $n caught by $property:"
      grep -A8 "^FAIL" <<< "$result" | sed 's/^/    /'
    else
      echo "mutant $n NOT caught (expected $property):"
      head -3 <<< "$result" | sed 's/^/    /'
    fi
  done
  echo "$caught of $n mutants caught"
  [[ $caught == "$n" ]]
}

case "${1:-}" in
  --mutants) mutants ;;
  --reviewed) fingerprint > "$REVIEWED"; echo "recorded $(wc -l < "$REVIEWED" | tr -d ' ') sources as reviewed" ;;
  --require-reviewed) note="$(staleness)"; [[ -z "$note" ]] || { echo "$note"; exit 1; } ;;
  --inputs-key) inputs_key ;;
  *)
    staleness
    build "$REPO/Cards" "$OUT/desk-check"
    "$OUT/desk-check" "${1:-3}"
    ;;
esac
