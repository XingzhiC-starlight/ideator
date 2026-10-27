#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DERIVED=build/ReleaseDerivedData
STAGE=build/dmg-staging
OUT=build/release
APP="$DERIVED/Build/Products/Release/Ideator.app"
RESOLVED=Cards.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

die() { echo "package.sh: $*" >&2; exit 1; }

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

codesign --verify --deep --strict --verbose=2 "$APP"

# A debuggable build lets any program running as the user read the API key out of Ideator's memory.
signature="$(codesign -dv "$APP" 2>&1)"
[[ "$signature" == *"flags="*"runtime"* ]] || die "Ideator is not signed with the hardened runtime"
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
[[ "$entitlements" != *get-task-allow* ]] || die "Ideator carries the get-task-allow debug entitlement"
echo "signing: hardened runtime, not debuggable"

sparkle="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$sparkle" ]] || die "Sparkle.framework is not in Ideator's Contents/Frameworks"
pinned="$(jq -r '.pins[] | select(.identity == "sparkle") | .state.version' "$RESOLVED")"
embedded="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$sparkle/Resources/Info.plist")"
[[ "$embedded" == "$pinned" ]] || die "Ideator embeds Sparkle $embedded, but Package.resolved pins $pinned"
grep -qF "includes Sparkle $pinned " "$APP/Contents/Resources/ThirdPartyNotices.txt" \
  || die "Cards/ThirdPartyNotices.txt is missing or does not name Sparkle $pinned: replace its text with the LICENSE of the Sparkle package"
echo "sparkle: $embedded, as pinned, with its notices"

# Signing policy, the one place that knows about the bypass. An ad-hoc app with the hardened runtime cannot
# load the Sparkle.framework inside it (dyld: "different Team IDs"), so until a Team ID signs the build,
# Release carries one entitlement that turns library validation off. With a Team ID the bypass must go.
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
      || die "${file#"$APP"/} has Team ID '${other:-none}', Ideator's is $team: sign everything in Contents/Frameworks with the app's identity, innermost first (Xcode signs Sparkle.framework itself, not the helpers inside it)"
  done < <(find "$APP/Contents/Frameworks" -type f -print0)
  echo "signing policy: Team ID $team, library validation on, embedded code signed by the same team"
fi

archs="$(lipo -archs "$APP/Contents/MacOS/Ideator")"
for arch in arm64 x86_64; do
  [[ " $archs " == *" $arch "* ]] || die "Ideator has no $arch slice (found: $archs)"
done
echo "architectures: $archs"

[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || die "Ideator has no AppIcon.icns"
icon="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$icon" == AppIcon ]] || die "Ideator's CFBundleIconName is '$icon', expected AppIcon"
echo "icon: AppIcon"

# A signature that verifies can still belong to an app dyld refuses to start. The scratch run on an empty
# folder writes no preferences and registers no shortcut.
scratch="$(mktemp -d)"
mkdir "$scratch/notes"
"$APP/Contents/MacOS/Ideator" -CardsFolder "$scratch/notes" >"$scratch/output" 2>&1 &
pid=$!
sleep 3
alive=NO
mapped=""
if kill -0 "$pid" 2>/dev/null; then
  alive=YES
  mapped="$(lsof -p "$pid" -Fn 2>/dev/null || true)"
  kill "$pid" 2>/dev/null || true
fi
status=0
wait "$pid" 2>/dev/null || status=$?
output="$(<"$scratch/output")"
rm -rf "$scratch"
[[ "$alive" == YES ]] || die "Ideator exited with status $status within 3 seconds of launch${output:+: $output}"
grep -q '/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle$' <<<"$mapped" \
  || die "Ideator is running without Sparkle.framework mapped in"
echo "launch: ran for 3 seconds on an empty folder, with Sparkle loaded"

rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE/root" "$OUT"
ditto "$APP" "$STAGE/root/Ideator.app"
ln -s /Applications "$STAGE/root/Applications"

# The image is verified before it moves into $OUT, so a failed check never leaves a dmg there.
hdiutil create -quiet -volname Ideator -srcfolder "$STAGE/root" -format UDZO "$STAGE/Ideator.dmg"
hdiutil verify -quiet "$STAGE/Ideator.dmg"
echo "disk image: verified"
mv "$STAGE/Ideator.dmg" "$dmg"

echo "$PWD/$dmg"
