#!/bin/bash
# Publishes the tip of origin/main as a GitHub release that installed copies update to.
#   scripts/release.sh NOTES.md            build, sign and check, then make a draft release
#   scripts/release.sh --dry-run NOTES.md  the same, without writing to GitHub
#   scripts/release.sh --publish TAG       make the draft live, then wait until the feed serves it
# Each step looks at what exists first, so running the command again carries on where it stopped.
set -euo pipefail

mode=draft
case "${1:-}" in
  --dry-run) mode=dry-run; shift ;;
  --publish) mode=publish; shift ;;
esac
[[ $# -eq 1 && "$1" != -* ]] || { echo "usage: scripts/release.sh [--dry-run] NOTES.md | --publish TAG" >&2; exit 2; }
arg="$1"
notes=""
if [[ $mode != publish ]]; then
  notes="$arg"
  [[ "$notes" == /* ]] || notes="$PWD/$notes"
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."

app=build/ReleaseDerivedData/Build/Products/Release/Ideator.app
sparkle=build/ReleaseDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
out=build/release
account=ideator

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

die() { echo "release.sh: $*" >&2; exit 1; }

[[ "$(git branch --show-current)" == main ]] || die "not on main: a release is the tip of origin/main"
git fetch --quiet origin || die "git fetch origin failed"
tip="$(git rev-parse HEAD)"
[[ "$tip" == "$(git rev-parse origin/main)" ]] \
  || die "HEAD ${tip:0:7} is not origin/main $(git rev-parse --short origin/main): pull or push until they match"
[[ -z "$(git status --porcelain)" ]] \
  || die "the tree has changes, untracked files included: commit or remove them (keep the notes file outside the checkout)"
gh auth status >/dev/null 2>&1 || die "gh is not logged in: run gh auth login"
[[ $mode == publish || -s "$notes" ]] || die "$notes is missing or empty: write the release notes first"
echo "preconditions: main at ${tip:0:7}, clean, gh logged in"

[[ $mode == publish ]] || scripts/package.sh

[[ -d "$app" ]] || die "no build at $app: run scripts/release.sh NOTES.md first"
info() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist"; }
version="$(info CFBundleShortVersionString)"
build="$(info CFBundleVersion)"
commit="$(info IdeatorCommit)"
feed="$(info SUFeedURL)"
key="$(info SUPublicEDKey)"

# The feed URL is the one place the project names its repository.
[[ "$feed" =~ ^https://github\.com/([^/]+/[^/]+)/releases/latest/download/appcast\.xml$ ]] \
  || die "SUFeedURL is $feed, not a GitHub releases/latest/download/appcast.xml URL"
repo="${BASH_REMATCH[1]}"
export GH_REPO="$repo"
tag="v$version-$build"
dmg="$out/Ideator-$version-$build.dmg"
prefix="https://github.com/$repo/releases/download/$tag/"
[[ $mode != publish || "$tag" == "$arg" ]] \
  || die "the local build is $tag, not $arg, so it is not the build that draft was made from: make the draft again with scripts/release.sh NOTES.md"
echo "release: $tag, commit ${commit:0:7}, $repo"

# gh exits 1 for a missing release and for every other failure, so only its own message means "none".
release_state() {
  local view
  if view="$(gh release view "$tag" --json isDraft --jq .isDraft 2>&1)"; then
    case "$view" in true) echo draft ;; *) echo published ;; esac
  elif [[ "$view" == *"release not found"* ]]; then
    echo none
  else
    die "gh release view $tag failed: $view"
  fi
}

newer() {
  local status live
  status="$(curl -sSL -o "$tmp/live.xml" -w '%{http_code}' "$feed")" || die "cannot reach $feed"
  case "$status" in
    404) echo "feed: none yet, so this is the first release" ;;
    200)
      live="$(python3 -I -c 'import sys, xml.etree.ElementTree as ET
ns = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
print(max(int(v.text) for v in ET.parse(sys.argv[1]).iterfind(".//s:version", ns)))' "$tmp/live.xml")" \
        || die "the live feed at $feed has no sparkle:version"
      ((live < build)) || die "the live feed already offers build $live, and this is build $build: only a higher build can follow it"
      echo "feed: offers build $live, below $build" ;;
    *) die "$feed answered HTTP $status" ;;
  esac
}

# The draft's files are the ones that go live, so they are compared with the local ones, byte for byte.
assets_match() {
  rm -rf "$tmp/draft"
  gh release download "$tag" --dir "$tmp/draft" --pattern "$(basename "$dmg")" --pattern appcast.xml
  for file in "$dmg" "$out/appcast.xml"; do
    cmp -s "$tmp/draft/$(basename "$file")" "$file" || die "the draft's $(basename "$file") differs from $file"
  done
  echo "assets: $(basename "$dmg") and appcast.xml on GitHub are byte for byte the local files"
}

state="$(release_state)"

if [[ $mode == publish ]]; then
  [[ -f "$dmg" && -f "$out/appcast.xml" ]] || die "no local $dmg and $out/appcast.xml to compare the draft with: run scripts/release.sh NOTES.md again"
  case "$state" in
    none) die "$repo has no release $tag: run scripts/release.sh NOTES.md first" ;;
    draft)
      assets_match
      newer
      gh release edit "$tag" --draft=false --latest
      echo "published: $tag is the latest release" ;;
    *) echo "published: $tag was already live" ;;
  esac
  for _ in $(seq 24); do
    if curl -fsSL -o "$tmp/live.xml" "$feed" 2>/dev/null && cmp -s "$tmp/live.xml" "$out/appcast.xml"; then
      echo "feed: $feed now serves the appcast checked before publishing"
      echo "installed copies below build $build are offered Ideator $version at their next daily check, or at once through Check for Updates…"
      exit 0
    fi
    sleep 5
  done
  die "$feed does not serve $out/appcast.xml 120 seconds after publishing: look at it with curl -L, then run this again"
fi

[[ "$state" != published ]] || { echo "$tag is already released"; exit 0; }

held="$("$sparkle/generate_keys" --account "$account" -p)" || die "generate_keys cannot read the key for account $account"
[[ "$held" == "$key" ]] \
  || die "the Keychain's key ($held) is not the one the app trusts ($key): restore the key from the Passwords backup with generate_keys --account $account -f FILE"
echo "key: the Keychain's key is the one the app trusts"

newer

# generate_appcast extends a feed that already exists at -o instead of starting over.
rm -f "$out/appcast.xml"
stage="$out/feed"
rm -rf "$stage"
mkdir "$stage"
cp "$dmg" "$stage"
cp "$notes" "$stage/$(basename "$dmg" .dmg).md"
"$sparkle/generate_appcast" --account "$account" --embed-release-notes --maximum-versions 1 \
  --download-url-prefix "$prefix" -o "$out/appcast.xml" "$stage"

fields="$(python3 -I - "$out/appcast.xml" "$build" "$version" "$dmg" "$prefix" <<'PY'
import os, sys
import xml.etree.ElementTree as ET

path, build, version, dmg, prefix = sys.argv[1:]
sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"

def fail(why):
    sys.exit("release.sh: appcast: " + why)

items = ET.parse(path).getroot().findall("channel/item")
if len(items) != 1:
    fail(f"expected one item, found {len(items)}")
item = items[0]
enclosure = item.find("enclosure")
if enclosure is None:
    fail("the item has no enclosure")

def child(name):
    node = item.find(sparkle + name)
    return "" if node is None else (node.text or "").strip()

fields = {
    "sparkle:version": (child("version"), build),
    "sparkle:shortVersionString": (child("shortVersionString"), version),
    "enclosure url": (enclosure.get("url"), prefix + os.path.basename(dmg)),
    "enclosure length": (enclosure.get("length"), str(os.path.getsize(dmg))),
}
for name, (got, want) in fields.items():
    if got != want:
        fail(f"{name} is {got!r}, expected {want!r}")
minimum = child("minimumSystemVersion")
if not minimum.startswith("15.0"):
    fail(f"sparkle:minimumSystemVersion is {minimum!r}, expected 15.0")
if not (item.findtext("description") or "").strip():
    fail("the item has no release notes")
signature = enclosure.get(sparkle + "edSignature")
if not signature:
    fail("the enclosure has no sparkle:edSignature: generate_appcast did not sign it with the key the app trusts")

for name, (got, _) in fields.items():
    print(f"{name}: {got}")
print(f"sparkle:minimumSystemVersion: {minimum}")
print(f"signature: {signature}")
PY
)"
echo "appcast: one item, checked"
sed 's/^/  /' <<<"$fields"
signature="$(sed -n 's/^signature: //p' <<<"$fields")"

"$sparkle/sign_update" --account "$account" --verify "$dmg" "$signature" >/dev/null \
  || die "the disk image does not match the signature in its appcast item"
"$sparkle/sign_update" --account "$account" --verify "$out/appcast.xml" >/dev/null \
  || die "the appcast does not match the signature embedded in it"
echo "signatures: the disk image and the feed verify"

[[ $mode != dry-run ]] || { echo "dry run: $out/appcast.xml is ready and nothing was written to GitHub"; exit 0; }

title="Ideator $version ($build)"
if [[ "$state" == draft ]]; then
  gh release upload "$tag" "$dmg" "$out/appcast.xml" --clobber
  gh release edit "$tag" --title "$title" --notes-file "$notes"
else
  gh release create "$tag" --draft --target "$commit" --title "$title" --notes-file "$notes" "$dmg" "$out/appcast.xml"
fi
assets_match
echo "draft: $(gh release view "$tag" --json url --jq .url)"
echo "Read it, then run: scripts/release.sh --publish $tag"
