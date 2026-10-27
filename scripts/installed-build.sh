#!/bin/bash
# Says whether an installed Ideator is the current origin/main, from the commit package.sh stamped into it.
# Usage: scripts/installed-build.sh [APP]    (APP defaults to /Applications/Ideator.app)
# Exit status: 0 when the app is current, 1 for any other verdict.
set -euo pipefail

app="${1:-/Applications/Ideator.app}"
# `defaults read` takes a relative path for a domain name, so the path must be absolute before the cd.
[[ "$app" == /* ]] || app="$PWD/$app"
plist="$app/Contents/Info.plist"

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() { echo "installed-build.sh: $*" >&2; exit 1; }
info() { defaults read "$plist" "$1" 2>/dev/null || true; }
verdict() { echo "verdict:     $1"; exit "$2"; }

[[ -f "$plist" ]] || die "no app at $app"
[[ -n "$(info CFBundleVersion)" ]] || die "cannot read $plist"
name="Ideator $(info CFBundleShortVersionString) ($(info CFBundleVersion))"
commit="$(info IdeatorCommit)"
dirty="$(info IdeatorTreeDirty)"

# The same rule as BuildInfo.Stamp: "none" and "unknown" are what an Xcode build carries.
if ! [[ "$commit" =~ ^[0-9a-f]{40}$ && ( "$dirty" == YES || "$dirty" == NO ) ]]; then
  echo "installed:   $name, unstamped"
  verdict "can't tell. This build has no commit stamp: it is older than the stamp, or scripts/package.sh did not make it." 1
fi

git fetch --quiet origin main || echo "installed-build.sh: could not reach origin, using the origin/main fetched last" >&2
main="$(git rev-parse --verify --quiet origin/main)" || die "this clone has no origin/main"

tree=clean
[[ "$dirty" == NO ]] || tree="with local changes"
echo "installed:   $name, commit ${commit:0:7}, $tree"
echo "origin/main: ${main:0:7}"

if [[ "$dirty" == YES ]]; then
  verdict "not current. It was built with local changes, so its files are not any commit's." 1
elif [[ "$commit" == "$main" ]]; then
  verdict "current. Built from the tip of origin/main." 0
elif ! git cat-file -e "$commit^{commit}" 2>/dev/null; then
  verdict "not on origin/main. This clone does not have commit ${commit:0:7}." 1
elif [[ "$(git rev-parse "$commit^{tree}")" == "$(git rev-parse "$main^{tree}")" ]]; then
  verdict "current. Same files as origin/main, as a branch build has after its squash merge." 0
elif git merge-base --is-ancestor "$commit" "$main"; then
  behind="$(git rev-list --count "$commit..$main")"
  unit=commits
  [[ "$behind" != 1 ]] || unit=commit
  verdict "behind by $behind $unit. Install a newer build of origin/main." 1
else
  verdict "not on origin/main. It is a branch build, or older than a squash merge." 1
fi
