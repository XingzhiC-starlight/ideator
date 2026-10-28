#!/bin/bash
# Runs sample cards through the app's own summary request and checks each summary against the
# rules in CARDS-SPEC.md § AI summaries that a program can check. It compiles the real
# Cards/{Summarizer,Desk,Grid,Note}.swift with scripts/check-summaries/main.swift, so the request is
# the one the app sends, not a second implementation. It sends the sample cards (text in
# main.swift, no notes of yours) to the company the key belongs to.
#
# Usage: scripts/check-summaries.sh [--anthropic]
#   The OpenAI key is read from $OPENAI_API_KEY, else from a hidden prompt. It is never an
#   argument and is never printed or stored. --anthropic also runs the Anthropic request, key from
#   $ANTHROPIC_API_KEY or a second hidden prompt, to compare.
# Exit status: 0 when every request worked and every hard rule passed (heuristic warnings do not
#   count), 1 when not, 2 without a key.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/build/check-summaries"
mkdir -p "$OUT"
rm -f "$OUT/check-summaries"

swiftc -O "$REPO/Cards/Summarizer.swift" "$REPO/Cards/Desk.swift" "$REPO/Cards/Grid.swift" "$REPO/Cards/Note.swift" \
  "$REPO/scripts/check-summaries/main.swift" -o "$OUT/check-summaries" 2>&1 | grep -E "error" || true
[[ -x "$OUT/check-summaries" ]] || { echo "check-summaries.sh: did not compile" >&2; exit 2; }

exec "$OUT/check-summaries" "$@"
