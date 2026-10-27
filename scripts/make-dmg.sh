#!/bin/bash
set -euo pipefail

app="${1:?usage: make-dmg.sh APP DMG}"
dmg="${2:?usage: make-dmg.sh APP DMG}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/root"
ditto "$app" "$stage/root/Ideator.app"
ln -s /Applications "$stage/root/Applications"

# The image is verified before it moves into place, so a failed check never leaves a dmg there.
hdiutil create -quiet -volname Ideator -srcfolder "$stage/root" -format UDZO "$stage/Ideator.dmg"
hdiutil verify -quiet "$stage/Ideator.dmg"
mv "$stage/Ideator.dmg" "$dmg"
