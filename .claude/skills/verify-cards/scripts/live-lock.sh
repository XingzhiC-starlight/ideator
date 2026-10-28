#!/bin/bash
# The live-UI lock: one live Ideator session at a time on this Mac. Sourced by cards-verify and
# scripts/verify-update.sh. The lock is a directory; other agents take it by hand with `mkdir` and
# write a `holder` file inside, so this file keeps that exact path and shape.

# IDEATOR_LIVE_LOCK moves the lock elsewhere so a test can try the refusals without blocking anyone.
LIVE_LOCK="${IDEATOR_LIVE_LOCK:-/tmp/claude-$(id -u)/ideator-live-ui.lock}"

live_lock_holder() {
  if [[ ! -d "$LIVE_LOCK" ]]; then
    echo none
  elif [[ -s "$LIVE_LOCK/holder" ]]; then
    tr '\n' ' ' < "$LIVE_LOCK/holder" | sed 's/ *$//'
    echo
  else
    echo "unknown (no holder file)"
  fi
}

live_lock_take() {  # $1: the holder line; fails when anyone holds the lock
  mkdir -p "$(dirname "$LIVE_LOCK")"
  mkdir "$LIVE_LOCK" 2>/dev/null || return 1
  printf '%s\n' "$1" > "$LIVE_LOCK/holder"
}

live_lock_held_by() {  # $1: the holder line
  [[ -f "$LIVE_LOCK/holder" && "$(<"$LIVE_LOCK/holder")" == "$1" ]]
}

live_lock_release() {  # $1: the holder line; removes the lock only while its holder file is exactly that line
  live_lock_held_by "$1" || return 1
  rm -f "$LIVE_LOCK/holder"
  rmdir "$LIVE_LOCK"
}
