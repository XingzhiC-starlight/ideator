#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

DERIVED=build/ReleaseDerivedData
STAGE=build/dmg-staging
OUT=build/release
APP="$DERIVED/Build/Products/Release/Ideator.app"

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
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -quiet build \
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
entitlements="$(codesign -d --entitlements - "$APP" 2>/dev/null)"
[[ "$entitlements" != *get-task-allow* ]] || die "Ideator carries the get-task-allow debug entitlement"
echo "signing: hardened runtime, not debuggable"

archs="$(lipo -archs "$APP/Contents/MacOS/Ideator")"
for arch in arm64 x86_64; do
  [[ " $archs " == *" $arch "* ]] || die "Ideator has no $arch slice (found: $archs)"
done
echo "architectures: $archs"

[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || die "Ideator has no AppIcon.icns"
icon="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$icon" == AppIcon ]] || die "Ideator's CFBundleIconName is '$icon', expected AppIcon"
echo "icon: AppIcon"

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
