# Sourced by package.sh, verify-update.sh and test-signing.sh. Expects the caller's die().
#
# Two worlds. Until a Team ID signs the build, the app is ad hoc with the hardened runtime and one
# entitlement that turns library validation off (Config/Ideator-adhoc.entitlements). With a Team ID the
# entitlement is gone and everything inside the app must carry the app's Team ID.

# "not set" for an ad-hoc signature.
app_team() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }

# What codesign --sign takes to sign as $1 does: "-" for ad hoc, else the name of its certificate.
app_identity() {
  local team name
  team="$(app_team "$1")"
  [[ -n "$team" ]] || die "codesign reports no TeamIdentifier for $1"
  if [[ "$team" == "not set" ]]; then
    echo -
    return
  fi
  name="$(codesign -dvv "$1" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
  [[ -n "$name" ]] || die "$1 has Team ID $team but codesign names no signing identity (no Authority line)"
  echo "$name"
}

# Signing any program inside Sparkle.framework breaks the seal of everything around it, and what Xcode
# left on those programs is not something to rely on, so each is signed again, innermost first. The
# helpers keep no entitlements (Autoupdate arrives with Sparkle's own application-identifier). The AI
# tools helper (Contents/Helpers/ideator-mcp) keeps the identifier Xcode gave it. The app keeps the
# entitlements its build gave it. A missing helper is skipped; package.sh's Team ID check names any it
# still finds unsigned. Nothing happens for an ad-hoc app.
sign_for_release() {
  local app="$1" framework="$1/Contents/Frameworks/Sparkle.framework" helper="$1/Contents/Helpers/ideator-mcp" identity path
  local sign=(--force --options runtime --timestamp)
  [[ "$(app_team "$app")" != "not set" ]] || return 0
  identity="$(app_identity "$app")"
  [[ -d "$framework" ]] || die "Sparkle.framework is not in $app/Contents/Frameworks"
  for path in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    [[ ! -e "$framework/Versions/Current/$path" ]] \
      || codesign "${sign[@]}" --sign "$identity" "$framework/Versions/Current/$path"
  done
  codesign "${sign[@]}" --sign "$identity" "$framework"
  [[ ! -e "$helper" ]] || codesign "${sign[@]}" --preserve-metadata=identifier --sign "$identity" "$helper"
  codesign "${sign[@]}" --preserve-metadata=entitlements --sign "$identity" "$app"
  echo "signing: Sparkle's helpers, Sparkle.framework, the AI tools helper and the app signed with $identity"
}

# Seals a copy of the shipped app again after its Info.plist changed, as the app was sealed: with
# identity $1 (from app_identity) and the entitlements in file $3 when it holds any. Embedded code
# keeps its own signatures, which already carry the shipped app's team.
seal_copy() {
  local identity="$1" app="$2" entitlements="${3:-}"
  local args=(--force --options runtime)
  [[ ! -s "$entitlements" ]] || args+=(--entitlements "$entitlements")
  codesign "${args[@]}" --sign "$identity" "$app"
}
