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
#   count), 1 when not, 2 without a usable key (one pasted twice, or the other company's key at a
#   prompt) or when it did not compile.
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
# (no echo, no length limit), trimmed. $3 is the company the key must be for: a key pasted twice or
# a key for the other company exits 2 before any request. Prints one line naming the company and
# the key's length.
read_key() {
  local variable="$1" label="$2" company="$3" value="${!1:-}"
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
    echo "check-summaries.sh: the $company key has a space or a line break inside it, so it is not one key. Paste it again, on one line." >&2
    exit 2
  fi
  local half=$((${#value} / 2))
  if (( ${#value} % 2 == 0 )) && [[ "${value:0:half}" == "${value:half}" ]]; then
    echo "check-summaries.sh: the $company key looks pasted twice: its first half is the same as its second half. Run it again and paste the key once." >&2
    exit 2
  fi
  if [[ "$company" == OpenAI && "$value" == sk-ant-* ]]; then
    echo "check-summaries.sh: the key given as the $company key is an Anthropic key (it starts with sk-ant-). Run it again with your OpenAI key here; an Anthropic key goes at the second prompt, with --anthropic." >&2
    exit 2
  fi
  if [[ "$company" == Anthropic && "$value" != sk-ant-* ]]; then
    echo "check-summaries.sh: the key given as the $company key does not start with sk-ant-, so it is not an Anthropic key. Run it again with your Anthropic key here, not the OpenAI one." >&2
    exit 2
  fi
  echo "Read an $company key, ${#value} characters." >&2
  KEY_RESULT="$value"
}

read_key OPENAI_API_KEY "OpenAI key" OpenAI
OPENAI="$KEY_RESULT"
ANTHROPIC=""
if [[ " $* " == *" --anthropic "* ]]; then
  read_key ANTHROPIC_API_KEY "Anthropic key, for comparison" Anthropic
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
