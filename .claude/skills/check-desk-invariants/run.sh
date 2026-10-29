#!/bin/bash
# Bounded exhaustive check of the real Desk rules. See SKILL.md.
#
#   run.sh [DEPTH]        build against the current Cards/*.swift and check (default depth 3, ~10 s)
#   run.sh --mutants      break the code twenty known ways; each must be caught by its property
#   run.sh --reviewed     record the current Desk/Grid/Note sources as reviewed against the properties
#   run.sh --require-reviewed   fail while those sources differ from the reviewed ones (CI runs this)
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

staleness() {
  if [[ ! -f "$REVIEWED" ]] || ! diff -q <(fingerprint) "$REVIEWED" >/dev/null; then
    echo "note: Cards/{Desk,Grid,Note}.swift changed since the properties were last reviewed."
    echo "      Read the diff against SKILL.md's 'When the code changes', then run: run.sh --reviewed"
  fi
}

# Each mutant: property it must break | exact text in Cards/Desk.swift | replacement.
MUTANTS=(
  "P1 conservation|insertCard(popped.remove(at: i).card, at: 0)|_ = popped.remove(at: i)"
  "P2 places|            setPlace(of: occupant, to: from)|            _ = occupant"
  "P2 places|guard popped.count < Slot.count - 1 else { return nil }|"
  "P3 stack page|if i <= selection { selection += 1 }|"
  "P4 stack order|insertCard(Card(id: id, note: note, collapsed: clarity), at: stack.count)|insertCard(Card(id: id, note: note, collapsed: clarity), at: 0)"
  "P5 save and reload|stackFree: stackPlace.savedFree,|stackFree: nil,"
  "P6 clarity|        for i in stack.indices { stack[i].collapsed = clarity }|"
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
  "P6 clarity|let card = Card(id: freshID(at: date), note: note, collapsed: clarity)|let card = Card(id: freshID(at: date), note: note, collapsed: false)"
)

mutants() {
  local caught=0 n=0
  for m in "${MUTANTS[@]}"; do
    IFS='|' read -r property from to <<< "$m"
    n=$((n + 1))
    local dir="$OUT/mutant-$n"
    rm -rf "$dir"; mkdir -p "$dir"
    cp "${SOURCES[@]/#/$REPO/Cards/}" "$dir/"
    if ! FROM="$from" TO="$to" perl -0 -i -pe 'BEGIN { $n = 0 } $n += s/\Q$ENV{FROM}\E/$ENV{TO}/g; END { exit($n == 1 ? 0 : 3) }' "$dir/Desk.swift"; then
      echo "mutant $n ($property): its text is no longer in Desk.swift exactly once; update MUTANTS in run.sh"
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
  *)
    staleness
    build "$REPO/Cards" "$OUT/desk-check"
    "$OUT/desk-check" "${1:-3}"
    ;;
esac
