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
#   The keys are read here, before the compile, so the prompt shows at once and nothing pasted during
#   the compile is echoed. They reach the program only through its environment.
# Exit status: 0 when every request worked and every hard rule passed (heuristic warnings do not
#   count), 1 when not, 2 without a usable key or when it did not compile.
set -euo pipefail

case "${1:-}" in
  --help | -h)
    cat <<'USAGE'
check-summaries.sh              sample cards through the OpenAI request; key from $OPENAI_API_KEY or a hidden prompt
check-summaries.sh --anthropic  also through the Anthropic request; key from $ANTHROPIC_API_KEY or a hidden prompt
USAGE
    exit 0
    ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/build/check-summaries"

# Sets KEY_RESULT to the key from the variable named $1, else from a hidden read of the terminal
# (no echo, no length limit), trimmed. Prints one line naming the key's company and its length.
read_key() {
  local variable="$1" label="$2" value="${!1:-}"
  if [[ -z "${value//[[:space:]]/}" ]]; then
    value=""
    if (: </dev/tty) 2>/dev/null; then
      printf '%s (input hidden, empty to skip): ' "$label" >&2
      IFS= read -rs value </dev/tty || true
      printf '\n' >&2
    fi
  fi
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  KEY_RESULT=""
  [[ -n "$value" ]] || return 0
  if [[ "$value" == *[[:space:]]* ]]; then
    echo "check-summaries.sh: the $label has a space or a line break inside it, so it is not one key. Paste it again, on one line." >&2
    exit 2
  fi
  local company="an OpenAI"
  [[ "$value" == sk-ant-* ]] && company="an Anthropic"
  echo "Read $company key, ${#value} characters." >&2
  KEY_RESULT="$value"
}

read_key OPENAI_API_KEY "OpenAI key"
OPENAI="$KEY_RESULT"
ANTHROPIC=""
if [[ " $* " == *" --anthropic "* ]]; then
  read_key ANTHROPIC_API_KEY "Anthropic key, for comparison"
  ANTHROPIC="$KEY_RESULT"
fi

if [[ -z "$OPENAI$ANTHROPIC" ]]; then
  echo "No key. Set OPENAI_API_KEY, or run this in a terminal and paste a key at the hidden prompt." >&2
  exit 2
fi

mkdir -p "$OUT"
rm -f "$OUT/check-summaries"

swiftc -O "$REPO/Cards/Summarizer.swift" "$REPO/Cards/Desk.swift" "$REPO/Cards/Grid.swift" "$REPO/Cards/Note.swift" \
  "$REPO/scripts/check-summaries/main.swift" -o "$OUT/check-summaries" 2>&1 | grep -E "error" || true
[[ -x "$OUT/check-summaries" ]] || { echo "check-summaries.sh: did not compile" >&2; exit 2; }

OPENAI_API_KEY="$OPENAI" ANTHROPIC_API_KEY="$ANTHROPIC" exec "$OUT/check-summaries" "$@"
