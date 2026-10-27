#!/bin/bash
# Proves on this Mac that an installed Ideator build N updates itself to N+1 through Sparkle, from the
# disk image scripts/package.sh made. Local only: it drives the app through Accessibility, as verify-cards does.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

domain=com.systemlabs.Ideator.UpdateTest
sparkle=build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
lock="/tmp/claude-$(id -u)/ideator-live-ui.lock"
generate_cache="$HOME/Library/Caches/Sparkle_generate_appcast"
owner_app=/Applications/Ideator.app

work="" ev="" pid="" locked=0 feed_pid="" decoy_pid=""
[[ -d "$generate_cache" ]] && cache_existed=1 || cache_existed=0

owner_state() {
  local listing
  listing="$(find "$HOME/Documents/Ideator" -exec stat -f '%N %z %m' {} + 2>/dev/null | sort || true)"
  echo "defaults $(defaults export com.systemlabs.Ideator - 2>/dev/null | shasum | cut -c1-12)"
  echo "app $(codesign -dvvv "$owner_app" 2>&1 | sed -n 's/^CDHash=//p')"
  echo "pids $(pgrep -f "^$owner_app/Contents/MacOS/Ideator\$" | paste -sd, -)"
  echo "documents $(grep -c . <<<"$listing") entries, $(shasum <<<"$listing" | cut -c1-12)"
}

diagnose() {
  "$ax" tree "$pid" >"$ev/failure.tree.txt" 2>&1 || true
  /usr/bin/log show --last 5m --style compact \
    --predicate "processID == $pid AND (subsystem == \"org.sparkle-project.Sparkle\" OR category == \"connection\")" \
    >"$ev/failure.log" 2>&1 || true
  echo "verify-update: the accessibility tree and log of pid $pid are in $ev/failure.*" >&2
}

die() {
  echo "verify-update: $*" >&2
  [[ -z "$pid" ]] || diagnose
  exit 1
}

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  for server in "$feed_pid" "$decoy_pid"; do
    [[ -z "$server" ]] || { kill "$server" 2>/dev/null; wait "$server" 2>/dev/null; }
  done
  if [[ -n "$work" ]]; then
    pkill -f "$work/" 2>/dev/null && sleep 1
    hdiutil detach -quiet "$work/mnt" 2>/dev/null
    # Sparkle starts its Updater.app from inside the installed bundle, and Launch Services registers it.
    updater=install/Ideator.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app
    for app in shipped.app old.app new.app install/Ideator.app "$updater"; do "$lsregister" -u "$work/$app" 2>/dev/null; done
  fi
  defaults delete "$domain" 2>/dev/null
  rm -f "$HOME/Library/Preferences/$domain.plist"
  rm -rf "$HOME/Library/Caches/$domain" "$HOME/Library/HTTPStorages/$domain" "$HOME/Library/HTTPStorages/$domain.binarycookies"
  ((cache_existed)) || rm -rf "$generate_cache"
  [[ -z "$work" ]] || rm -rf "$work"
  if [[ -f "${ev:+$ev/owner.before}" ]]; then
    owner_state >"$ev/owner.after"
    if diff "$ev/owner.before" "$ev/owner.after" >&2; then
      echo "PASS: the owner's Ideator is untouched: $(paste -sd';' "$ev/owner.after" | sed 's/;/; /g')"
    else
      echo "FAIL: the owner's Ideator changed during the run" >&2
      status=1
    fi
  fi
  ((locked)) && rmdir "$lock"
  exit $status
}
trap cleanup EXIT

compile() {
  [[ -x "$2" && ! "$1" -nt "$2" ]] || { mkdir -p "$(dirname "$2")"; swiftc -O "$1" -o "$2"; }
}

ax=build/verify-tools/cards-ax
test_key=build/verify-tools/test-key
compile .claude/skills/verify-cards/scripts/cards-ax.swift "$ax"
compile scripts/verify-update/test-key.swift "$test_key"

dmg="${1:-$(ls -t build/release/Ideator-*.dmg 2>/dev/null | head -1 || true)}"
[[ -f "$dmg" ]] || die "no disk image; run scripts/package.sh first"
for tool in generate_appcast sign_update; do
  [[ -x "$sparkle/$tool" ]] || die "$sparkle/$tool is missing; scripts/package.sh resolves Sparkle"
done

mkdir -p "$(dirname "$lock")"
mkdir "$lock" 2>/dev/null || die "another live Ideator session holds $lock"
locked=1

work="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/ideator-verify-update.XXXXXX")" && pwd -P)"
ev="$PWD/build/verify-evidence/update-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ev" "$work"/{mnt,install,folder,decoy}
owner_state >"$ev/owner.before"

free_port() { python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
port="$(free_port)"
decoy_port="$(free_port)"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }

# Without its signature, the executable is the same bytes in every copy of the same build. The rest is
# every file the seal covers except the plist, which the fixtures change on purpose.
code_hash() {
  local copy="$work/executable"
  cp "$1/Contents/MacOS/Ideator" "$copy"
  codesign --remove-signature "$copy"
  shasum -a 256 "$copy" | cut -d' ' -f1
  rm -f "$copy"
  (cd "$1/Contents" && find . -type f ! -path ./Info.plist ! -path ./MacOS/Ideator ! -path ./_CodeSignature/CodeResources \
    -exec shasum -a 256 {} + | sort -k2 | shasum | cut -d' ' -f1)
}

same_code() { [[ "$(code_hash "$1")" == "$(code_hash "$2")" ]]; }

hdiutil attach -nobrowse -readonly -quiet -mountpoint "$work/mnt" "$dmg"
ditto "$work/mnt/Ideator.app" "$work/shipped.app"
hdiutil detach -quiet "$work/mnt"

built="$(plist "$work/shipped.app" CFBundleVersion)"
previous=$((built - 1))
short="$(plist "$work/shipped.app" CFBundleShortVersionString)"
echo "build under test: $short ($built), commit $(plist "$work/shipped.app" IdeatorCommit | cut -c1-7)," \
  "local changes: $(plist "$work/shipped.app" IdeatorTreeDirty), from $dmg"
codesign -d --entitlements - --xml "$work/shipped.app" >"$work/entitlements.plist" 2>/dev/null
[[ -s "$work/entitlements.plist" ]] || die "the shipped app has no entitlements to re-seal with"

public_key="$("$test_key" "$work/test.key")"
"$test_key" "$work/forger.key" >/dev/null

fixture() {
  ditto "$work/shipped.app" "$1"
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $domain" \
    -c "Set :CFBundleVersion $2" \
    -c "Set :SUFeedURL http://localhost:$port/releases/latest/download/appcast.xml" \
    -c "Set :SUPublicEDKey $public_key" \
    -c "Add :IdeatorUpdateTest string YES" "$1/Contents/Info.plist"
  codesign --force --options runtime --entitlements "$work/entitlements.plist" --sign - "$1"
}
fixture "$work/old.app" "$previous"
fixture "$work/new.app" "$built"
same_code "$work/shipped.app" "$work/old.app" || die "the fixture for build $previous runs different code than the shipped app"
same_code "$work/shipped.app" "$work/new.app" || die "the fixture for build $built runs different code than the shipped app"
diff <(plutil -p "$work/shipped.app/Contents/Info.plist") <(plutil -p "$work/new.app/Contents/Info.plist") >"$ev/fixture.plist.diff" || true
echo "fixtures differ from the shipped app in its Info.plist only:"
sed 's/^/  /' "$ev/fixture.plist.diff"

installed="$work/install/Ideator.app"
ditto "$work/old.app" "$installed"
scripts/make-dmg.sh "$work/old.app" "$work/previous.dmg"
scripts/make-dmg.sh "$work/new.app" "$work/built.dmg"

feed() {
  local dir="$work/feed-$1" disk_image="$2" build="$3"
  mkdir "$dir"
  cp "$disk_image" "$dir/Ideator-$short-$build.dmg"
  "$sparkle/generate_appcast" --ed-key-file "$work/test.key" \
    --download-url-prefix "http://localhost:$port/releases/download/test/" -o "$dir/appcast.xml" "$dir" \
    >"$ev/$1.generate_appcast.txt" 2>&1
  ! grep -q 'does not match' "$ev/$1.generate_appcast.txt" || die "generate_appcast does not hold the key the app trusts, so the item would be unsigned"
  grep -q 'sparkle:edSignature' "$dir/appcast.xml" || die "the appcast item for $1 is unsigned"
  "$sparkle/sign_update" --ed-key-file "$work/test.key" --verify "$dir/appcast.xml" >/dev/null || die "the $1 feed signature does not verify"
}
feed up-to-date "$work/previous.dmg" "$previous"
feed forged-feed "$work/built.dmg" "$built"
feed forged-disk-image "$work/built.dmg" "$built"
feed real-update "$work/built.dmg" "$built"

"$sparkle/sign_update" --ed-key-file "$work/forger.key" "$work/feed-forged-feed/appcast.xml" >/dev/null
! "$sparkle/sign_update" --ed-key-file "$work/test.key" --verify "$work/feed-forged-feed/appcast.xml" >/dev/null 2>&1 \
  || die "the forged feed still verifies against the key the app trusts"

# Flipped after the feed was signed, so the feed stays valid and only the archive is wrong.
tampered="$(echo "$work"/feed-forged-disk-image/*.dmg)"
python3 -I -c 'import sys
f = open(sys.argv[1], "r+b"); f.seek(4096); b = f.read(1); f.seek(4096); f.write(bytes([b[0] ^ 255]))' "$tampered"
! cmp -s "$tampered" "$work/built.dmg" || die "the forged disk image is the real one"

python3 -I scripts/verify-update/server.py "$decoy_port" "$work/decoy" >"$ev/decoy.log" 2>&1 &
decoy_pid=$!

hits() { grep -c -- "$1" "$2" || true; }
feed_requests() { hits 'GET /releases/download/test/appcast.xml' "$ev/$1.feed.log"; }
disk_image_requests() { hits 'GET /releases/download/test/Ideator-.*\.dmg' "$ev/$1.feed.log"; }
pid_of() { pgrep -n -f "^$installed/Contents/MacOS/Ideator\$" || true; }
disk_build() { plist "$installed" CFBundleVersion; }

tree() { "$ax" tree "$pid" 2>/dev/null || true; }

seen() {
  local seconds="$1" patterns=()
  shift
  for pattern in "$@"; do patterns+=(-e "$pattern"); done
  for _ in $(seq $((seconds * 2))); do
    grep -q -F "${patterns[@]}" <<<"$(tree)" && return 0
    sleep 0.5
  done
  return 1
}

wait_for() { seen "$@" || die "never saw '${*:2}' in pid $pid within ${1}s"; }

press() {
  for _ in $(seq 30); do
    "$ax" press "$pid" "$1" >/dev/null 2>&1 && return 0
    sleep 0.5
  done
  die "could not press '$1' in pid $pid"
}

snap() {
  "$ax" tree "$pid" >"$ev/$1.tree.txt" 2>&1 || true
  while read -r window _; do
    screencapture -x -o -l "$window" "$ev/$1-$window.png" 2>/dev/null || true
  done < <("$ax" windows "$pid" 2>/dev/null)
}

sparkle_log() {
  sleep 1
  /usr/bin/log show --last 5m --style compact \
    --predicate "processID == $pid AND subsystem == \"org.sparkle-project.Sparkle\"" >"$ev/$1.sparkle.log" 2>&1 || true
}

stop_app() {
  pkill -f "^$installed/Contents/MacOS/Ideator\$" 2>/dev/null || true
  for _ in $(seq 40); do [[ -z "$(pid_of)" ]] && return 0; sleep 0.25; done
  die "the installed build did not quit"
}

begin() {
  local name="$1" scheduled="${2:-}" dir="$work/feed-$1"
  python3 -I scripts/verify-update/server.py "$port" "$dir" >"$ev/$name.feed.log" 2>&1 &
  feed_pid=$!
  for _ in $(seq 50); do grep -q listening "$ev/$name.feed.log" && break; sleep 0.1; done
  grep -q listening "$ev/$name.feed.log" || die "the feed server for $name did not start"
  defaults delete "$domain" 2>/dev/null || true
  rm -rf "$HOME/Library/Caches/$domain"
  defaults write "$domain" CardsFolder "$work/folder"
  defaults write "$domain" SUFeedURL "http://localhost:$decoy_port/decoy.xml"
  [[ -n "$scheduled" ]] || defaults write "$domain" SUEnableAutomaticChecks -bool NO
  open -n --stdout "$ev/$name.app.log" --stderr "$ev/$name.app.log" "$installed"
  for _ in $(seq 60); do pid="$(pid_of)"; [[ -n "$pid" ]] && break; sleep 0.25; done
  [[ -n "$pid" ]] || die "build $previous did not start"
  wait_for 30 '"New"'
}

# The shortcut goes to the app only once it is active, and activation can lose a race with another app.
open_settings() {
  for attempt in 1 2 3 4 5; do
    "$ax" key "$pid" cmd+, >/dev/null 2>&1 || true
    if seen 4 "Check Now"; then
      ((attempt == 1)) || echo "  Settings opened on attempt $attempt"
      return 0
    fi
  done
  die "Settings did not open in pid $pid"
}

# A request that never reaches the feed server fails the check with this generic error, and the next check
# works, so it is tried again. An error about the feed's signature is a different message and a real result.
check_now() {
  open_settings
  for attempt in 1 2 3; do
    press "Check Now"
    wait_for 30 "up to date" "A new version of Ideator" "Update Error"
    grep -q -F "An error occurred in retrieving update information" <<<"$(tree)" || return 0
    ((attempt < 3)) || die "three checks in a row could not retrieve the feed"
    echo "  check $attempt could not retrieve the feed; checking again"
    press "Cancel Update"
  done
}

finish() {
  sparkle_log "$1"
  stop_app
  kill "$feed_pid"
  wait "$feed_pid" 2>/dev/null || true
  feed_pid=""
  pid=""
  [[ "$(hits GET "$ev/decoy.log")" == 0 ]] || die "the decoy feed from the SUFeedURL default was requested"
  [[ "$(disk_build)" == "$2" ]] || die "the build on disk is $(disk_build), expected $2"
}

begin up-to-date
check_now
wait_for 30 "up to date"
snap up-to-date
! grep -q "Install Update" "$ev/up-to-date.tree.txt" || die "an update was offered although the feed lists build $previous"
(($(feed_requests up-to-date) >= 1)) || die "the feed was never requested"
[[ "$(disk_image_requests up-to-date)" == 0 ]] || die "a disk image was requested although the feed lists build $previous"
finish up-to-date "$previous"
echo "PASS: up to date: feed fetched, 'up to date' shown, no disk image requested, build $previous stays"

begin forged-feed
check_now
wait_for 30 "update feed is improperly signed"
snap forged-feed
(($(feed_requests forged-feed) >= 1)) || die "the feed was never requested"
[[ "$(disk_image_requests forged-feed)" == 0 ]] || die "a disk image was requested from a feed signed by another key"
finish forged-feed "$previous"
echo "PASS: forged feed: signed by another key, refused, no disk image requested, build $previous stays"

begin forged-disk-image
check_now
wait_for 30 "A new version of Ideator is available"
press "Install Update"
wait_for 60 "The update is improperly signed"
snap forged-disk-image
[[ "$(disk_image_requests forged-disk-image)" == 1 ]] || die "expected one disk image request"
finish forged-disk-image "$previous"
echo "PASS: forged disk image: downloaded, refused as improperly signed, build $previous stays"

begin real-update scheduled
offered_by="the scheduled check at launch"
if ! seen 30 "A new version of Ideator is available"; then
  echo "  the scheduled check offered nothing within 30 s; checking by hand"
  offered_by="Check Now"
  check_now
  wait_for 30 "A new version of Ideator is available"
fi
snap real-update-offer
press "Install Update"
wait_for 90 "Install and Relaunch" "Update Error"
snap real-update-ready
! grep -q "Update Error" "$ev/real-update-ready.tree.txt" \
  || die "Sparkle refused the real update: $(grep -m1 -o 'value="The [^"]*"' "$ev/real-update-ready.tree.txt")"
old_pid="$pid"
# The press that works quits the app mid-call, so cards-ax reports it as failed.
for _ in $(seq 30); do
  "$ax" press "$old_pid" "Install and Relaunch" >/dev/null 2>&1 || true
  sleep 1
  kill -0 "$old_pid" 2>/dev/null || break
done
! kill -0 "$old_pid" 2>/dev/null || die "pid $old_pid kept running after Install and Relaunch"
for _ in $(seq 240); do
  pid="$(pid_of)"
  [[ -n "$pid" && "$pid" != "$old_pid" ]] && break
  sleep 0.25
done
[[ -n "$pid" && "$pid" != "$old_pid" ]] || { pid=""; die "Sparkle did not relaunch the app"; }
for _ in $(seq 60); do [[ "$(disk_build)" == "$built" ]] && break; sleep 0.5; done
[[ "$(disk_build)" == "$built" ]] || die "the build on disk is $(disk_build), expected $built"
wait_for 30 '"New"'
codesign --verify --deep --strict "$installed" || die "the installed build does not verify"
same_code "$work/shipped.app" "$installed" || die "the installed code differs from the shipped app"
[[ "$(cdhash "$installed")" == "$(cdhash "$work/new.app")" ]] || die "the installed build is not the one that was served"
open_settings
wait_for 30 "Version $short ($built)"
snap real-update-relaunched
press "Check Now"
wait_for 30 "up to date"
snap real-update-current
[[ "$(disk_image_requests real-update)" == 1 ]] || die "expected one disk image request in all"
(($(feed_requests real-update) >= 2)) || die "the relaunched build did not check the feed"
finish real-update "$built"
echo "PASS: real update: offered by $offered_by, $previous -> $built, new process, code equals the shipped app, the relaunched build reports $short ($built), a second check finds nothing and downloads nothing"
