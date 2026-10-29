#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DERIVED=build/ReleaseDerivedData
OUT=build/release
APP="$DERIVED/Build/Products/Release/Ideator.app"
RESOLVED=Cards.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

die() { echo "package.sh: $*" >&2; exit 1; }
source scripts/signing.sh

# The build number is the number of commits on HEAD, so every release from main gets a higher one
# without anyone editing it. Sparkle compares it to decide which build is newer.
[[ "$(git rev-parse --is-shallow-repository)" == false ]] || die "shallow clone: the build number needs full history"
build="$(git rev-list --count HEAD)"

# A commit count is not an identity: a branch build and main after its squash merge can share one. The
# app carries the commit and whether the tree had changes (untracked files included). They go in as
# build settings, so they are inside the signature; editing the plist afterwards would break it.
commit="$(git rev-parse HEAD)"
dirty=NO
[[ -z "$(git status --porcelain)" ]] || dirty=YES

xcodebuild -project Cards.xcodeproj -scheme Ideator -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -disableAutomaticPackageResolution -quiet build \
  CURRENT_PROJECT_VERSION="$build" IDEATOR_COMMIT="$commit" IDEATOR_TREE_DIRTY="$dirty"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
bundled="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$bundled" == "$build" ]] || die "the app's build number is $bundled, expected $build"
echo "version: $version ($build)"
dmg="$OUT/Ideator-$version-$build.dmg"

info() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true; }
[[ "$(info IdeatorCommit)" == "$commit" ]] || die "the app's commit is '$(info IdeatorCommit)', expected $commit"
[[ "$(info IdeatorTreeDirty)" == "$dirty" ]] || die "the app's tree state is '$(info IdeatorTreeDirty)', expected $dirty"
echo "stamp: commit $commit, local changes: $dirty"

# Sparkle's settings live in Config/Info.plist. A copy of the release key sits here on purpose: changing
# the key strands every installed copy, so it takes an edit in two places.
production_feed=https://github.com/XingzhiC-starlight/ideator/releases/latest/download/appcast.xml
release_key=aU79Ryz97RGp9XiQfDRmXkV4198Z8g6cp+8nhrIpaJ4=
[[ "$(info SUFeedURL)" == "$production_feed" ]] || die "the app's SUFeedURL is '$(info SUFeedURL)', not $production_feed"
[[ "$(info SUPublicEDKey)" == "$release_key" ]] || die "the app's SUPublicEDKey is '$(info SUPublicEDKey)', not the release key"
[[ "$(info SUEnableSystemProfiling)" == false ]] || die "SUEnableSystemProfiling must be false (PRIVACY.md)"
[[ "$(info SUAllowsAutomaticUpdates)" == false ]] || die "SUAllowsAutomaticUpdates must be false: Ideator asks before it installs"
[[ "$(info IdeatorUpdateTest)" =~ ^(NO)?$ ]] || die "IdeatorUpdateTest is '$(info IdeatorUpdateTest)': a release is not an update-test build"
[[ -z "$(info NSAppTransportSecurity)" ]] || die "Info.plist has NSAppTransportSecurity: the feed is https only"
echo "updates: the production feed and release key, no system profile, no automatic installs"

sign_for_release "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# A debuggable build lets any program running as the user read the API key out of Ideator's memory.
signature="$(codesign -dv "$APP" 2>&1)"
[[ "$signature" == *"flags="*"runtime"* ]] || die "Ideator is not signed with the hardened runtime"
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
[[ "$entitlements" != *get-task-allow* ]] || die "Ideator carries the get-task-allow debug entitlement"
echo "signing: hardened runtime, not debuggable"

# The MCP server AI tools run. It is notarized with the app, so it needs the same runtime and no debug entitlement.
helper="$APP/Contents/Helpers/ideator-mcp"
[[ -x "$helper" ]] || die "the AI tools helper is not at Contents/Helpers/ideator-mcp"
helper_signature="$(codesign -dv "$helper" 2>&1)"
[[ "$helper_signature" == *"flags="*"runtime"* ]] || die "ideator-mcp is not signed with the hardened runtime"
[[ "$(codesign -d --entitlements - --xml "$helper" 2>/dev/null)" != *get-task-allow* ]] \
  || die "ideator-mcp carries the get-task-allow debug entitlement"
[[ "$(sed -n 's/^TeamIdentifier=//p' <<<"$helper_signature")" == "$(sed -n 's/^TeamIdentifier=//p' <<<"$signature")" ]] \
  || die "ideator-mcp is not signed by Ideator's team"
echo "helper: Contents/Helpers/ideator-mcp, hardened runtime, not debuggable, Ideator's team"

sparkle="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$sparkle" ]] || die "Sparkle.framework is not in Ideator's Contents/Frameworks"
pinned="$(jq -r '.pins[] | select(.identity == "sparkle") | .state.version' "$RESOLVED")"
embedded="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$sparkle/Resources/Info.plist")"
[[ "$embedded" == "$pinned" ]] || die "Ideator embeds Sparkle $embedded, but Package.resolved pins $pinned"
grep -qF "includes Sparkle $pinned " "$APP/Contents/Resources/ThirdPartyNotices.txt" \
  || die "Cards/ThirdPartyNotices.txt is missing or does not name Sparkle $pinned: replace its text with the LICENSE of the Sparkle package"
echo "sparkle: $embedded, as pinned, with its notices"

# Signing policy. An ad-hoc app with the hardened runtime cannot load the Sparkle.framework inside it
# (dyld: "different Team IDs"), so until a Team ID signs the build, Release carries one entitlement that
# turns library validation off. With a Team ID the bypass must go, and sign_for_release has signed
# everything inside the app with the app's identity.
disable_validation=com.apple.security.cs.disable-library-validation
team="$(sed -n 's/^TeamIdentifier=//p' <<<"$signature")"
[[ -n "$team" ]] || die "codesign did not report a TeamIdentifier for Ideator"
if [[ "$team" == "not set" ]]; then
  keys="$(plutil -convert json -o - - <<<"$entitlements" 2>/dev/null || true)"
  [[ "$keys" == "{\"$disable_validation\":true}" ]] \
    || die "Ideator has no Team ID, so its entitlements must be exactly $disable_validation (found: ${keys:-none}); without it dyld refuses Sparkle.framework. Set CODE_SIGN_ENTITLEMENTS = Config/Ideator-adhoc.entitlements on the Ideator Release configuration."
  echo "signing policy: no Team ID, library validation off until the Developer ID arrives (see README)"
else
  [[ "$entitlements" != *"$disable_validation"* ]] \
    || die "Ideator has Team ID $team but still turns library validation off: delete Config/Ideator-adhoc.entitlements and its CODE_SIGN_ENTITLEMENTS line"
  while IFS= read -r -d '' file; do
    [[ "$(file -b "$file")" == Mach-O* ]] || continue
    other="$(codesign -dv "$file" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"
    [[ "$other" == "$team" ]] \
      || die "${file#"$APP"/} has Team ID '${other:-none}', Ideator's is $team: sign_for_release in scripts/signing.sh does not sign it (a program this Sparkle version ships that it does not list)"
  done < <(find "$APP/Contents/Frameworks" "$APP/Contents/Helpers" -type f -print0)
  echo "signing policy: Team ID $team, library validation on, embedded code signed by the same team"
fi

for program in MacOS/Ideator Helpers/ideator-mcp; do
  archs="$(lipo -archs "$APP/Contents/$program")"
  for arch in arm64 x86_64; do
    [[ " $archs " == *" $arch "* ]] || die "$program has no $arch slice (found: $archs)"
  done
done
echo "architectures: $archs, in Ideator and ideator-mcp"

[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || die "Ideator has no AppIcon.icns"
icon="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$icon" == AppIcon ]] || die "Ideator's CFBundleIconName is '$icon', expected AppIcon"
echo "icon: AppIcon"

# A signature that verifies can still belong to an app dyld refuses to start. The scratch run on an empty
# folder writes no preferences and registers no shortcut. The helper, given the same folder, reaches only
# that run, as an AI tool's call would reach the owner's Ideator.
# The run shows a real window, and keys typed for another live session can land in it, so the check
# takes the live-UI lock that cards-verify takes, waiting up to 30 minutes for it.
source .claude/skills/verify-cards/scripts/live-lock.sh
lock_token="scripts/package.sh pid $$ in $PWD since $(date '+%H:%M:%S')"
for attempt in $(seq 1 61); do
  live_lock_take "$lock_token" && break
  ((attempt < 61)) || die "another live Ideator session held $LIVE_LOCK for 30 minutes (holder: $(live_lock_holder))"
  echo "package.sh: waiting for $LIVE_LOCK, held by: $(live_lock_holder)" >&2
  sleep 30
done
trap 'live_lock_release "$lock_token" || true' EXIT
scratch="$(mktemp -d)"
mkdir "$scratch/notes"
"$APP/Contents/MacOS/Ideator" -CardsFolder "$scratch/notes" >"$scratch/output" 2>&1 &
pid=$!
sleep 3
alive=NO
mapped=""
handed=""
saved=""
if kill -0 "$pid" 2>/dev/null; then
  alive=YES
  mapped="$(lsof -p "$pid" -Fn 2>/dev/null || true)"
  handed="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"add_card","arguments":{"title":"Package check"}}}' \
    | perl -e 'alarm 20; exec @ARGV' "$helper" -CardsFolder "$scratch/notes" 2>&1 || true)"
  saved="$(cat "$scratch/notes"/*.md 2>/dev/null || true)"
  kill "$pid" 2>/dev/null || true
fi
status=0
wait "$pid" 2>/dev/null || status=$?
output="$(<"$scratch/output")"
rm -rf "$scratch"
[[ "$alive" == YES ]] || die "Ideator exited with status $status within 3 seconds of launch${output:+: $output}"
grep -q '/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle$' <<<"$mapped" \
  || die "Ideator is running without Sparkle.framework mapped in"
[[ "$handed" == *'"text":"Added \"Package check\" to the top of the stack."'* ]] \
  || die "ideator-mcp did not hand a card to the running Ideator: ${handed:-no reply}"
[[ "$saved" == "# Package check" ]] || die "Ideator replied to ideator-mcp but its folder holds: ${saved:-nothing}"
echo "launch: ran for 3 seconds on an empty folder, with Sparkle loaded, and saved the card ideator-mcp handed it"
live_lock_release "$lock_token" || echo "package.sh: $LIVE_LOCK is not held by this run (holder: $(live_lock_holder)); left alone" >&2
trap - EXIT

rm -rf "$OUT"
mkdir -p "$OUT"
scripts/make-dmg.sh "$APP" "$dmg"
echo "disk image: verified"

echo "$PWD/$dmg"
