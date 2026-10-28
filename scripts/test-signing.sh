#!/bin/bash
# Proves, with a stand-in for codesign, how package.sh and verify-update.sh sign in both worlds: ad hoc
# with the one entitlement (today), and a Team ID identity with no entitlement (the Developer ID day).
# Needs no Xcode, no build and no certificate.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
die() { echo "test-signing: $*" >&2; exit 1; }

mkdir "$tmp/bin"
cat >"$tmp/bin/codesign" <<'STUB'
#!/bin/bash
case "$1" in
  -d*) cat "$FAKE_REPORT" ;;
  *) (IFS='|'; echo "$*") >>"$FAKE_LOG" ;;
esac
STUB
chmod +x "$tmp/bin/codesign"
export PATH="$tmp/bin:$PATH" FAKE_REPORT="$tmp/report" FAKE_LOG="$tmp/log"

app="$tmp/Ideator.app"
framework="$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$framework/Versions/B/XPCServices/Installer.xpc" "$framework/Versions/B/XPCServices/Downloader.xpc" \
  "$framework/Versions/B/Updater.app"
touch "$framework/Versions/B/Autoupdate"
ln -s B "$framework/Versions/Current"

identity="Developer ID Application: Test Co (ABCDE12345)"
cat >"$tmp/team-report" <<REPORT
Identifier=com.systemlabs.Ideator
Authority=$identity
Authority=Developer ID Certification Authority
Authority=Apple Root CA
TeamIdentifier=ABCDE12345
REPORT
cat >"$tmp/adhoc-report" <<'REPORT'
Identifier=com.systemlabs.Ideator
Signature=adhoc
TeamIdentifier=not set
REPORT

source scripts/signing.sh || die "scripts/signing.sh does not load"

failed=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
  else
    failed=1
    echo "FAIL: $1" >&2
    echo "  expected: $3" >&2
    echo "  actual:   $2" >&2
  fi
}

run() { : >"$FAKE_LOG"; ( set -e; "$@" ) 2>&1; }
calls() { cat "$FAKE_LOG"; }
world() { cp "$tmp/$1-report" "$FAKE_REPORT"; }

nested="$framework/Versions/Current"
sign="--force|--options|runtime|--timestamp"

world team
output="$(run sign_for_release "$app")"
expect "a Team ID build signs Sparkle's helpers, then the framework, then the app, all with its identity" \
  "$(calls)" "$sign|--sign|$identity|$nested/XPCServices/Installer.xpc
$sign|--sign|$identity|$nested/XPCServices/Downloader.xpc
$sign|--sign|$identity|$nested/Autoupdate
$sign|--sign|$identity|$nested/Updater.app
$sign|--sign|$identity|$framework
$sign|--preserve-metadata=entitlements|--sign|$identity|$app"
expect "a Team ID build says what it signed" "$output" "signing: Sparkle's helpers, Sparkle.framework and the app signed with $identity"

paths=()
while IFS='|' read -r -a call; do paths+=("${call[${#call[@]}-1]}"); done <"$FAKE_LOG"
inside=""
for ((later = 1; later < ${#paths[@]}; later++)); do
  for ((earlier = 0; earlier < later; earlier++)); do
    [[ "${paths[later]}/" != "${paths[earlier]}/"* ]] || inside+="${paths[later]} after ${paths[earlier]}; "
  done
done
expect "no call signs a path inside one that was signed before it" "$inside" ""

rm -r "$framework/Versions/B/XPCServices"
run sign_for_release "$app" >/dev/null
expect "a helper Sparkle no longer ships is skipped" "$(calls | wc -l | tr -d ' ')" "4"
mkdir -p "$framework/Versions/B/XPCServices/Installer.xpc" "$framework/Versions/B/XPCServices/Downloader.xpc"

world adhoc
output="$(run sign_for_release "$app")"
expect "an ad-hoc build is not re-signed" "$(calls)" ""
expect "an ad-hoc build prints nothing" "$output" ""

world adhoc
expect "an ad-hoc build is signed with '-'" "$(app_identity "$app")" "-"
world team
expect "a Team ID build is signed with its certificate's name" "$(app_identity "$app")" "$identity"

echo '<plist/>' >"$tmp/entitlements.plist"
: >"$tmp/none.plist"
copy="$tmp/copy.app"

run seal_copy - "$copy" "$tmp/entitlements.plist" >/dev/null
expect "an ad-hoc fixture is sealed as it always was" "$(calls)" \
  "--force|--options|runtime|--entitlements|$tmp/entitlements.plist|--sign|-|$copy"
run seal_copy "$identity" "$copy" "$tmp/none.plist" >/dev/null
expect "a Team ID fixture with no entitlement is sealed with none" "$(calls)" \
  "--force|--options|runtime|--sign|$identity|$copy"
run seal_copy "$identity" "$copy" "$tmp/entitlements.plist" >/dev/null
expect "a Team ID fixture keeps the entitlements its app has" "$(calls)" \
  "--force|--options|runtime|--entitlements|$tmp/entitlements.plist|--sign|$identity|$copy"

cp "$tmp/team-report" "$FAKE_REPORT"
sed -i '' '/^Authority=/d' "$FAKE_REPORT"
output="$(run app_identity "$app")"
expect "a Team ID build whose certificate has no name stops" "$([[ "$output" == *"names no signing identity"* ]] && echo stopped)" "stopped"

world team
output="$(run sign_for_release "$tmp/Missing.app")"
expect "a Team ID build without Sparkle.framework stops before it signs anything" \
  "$([[ "$output" == *"Sparkle.framework"* && -z "$(calls)" ]] && echo stopped)" "stopped"

package_order="$(grep -n '^sign_for_release\|^codesign --verify' scripts/package.sh | cut -d: -f2- | cut -c1-24 | paste -sd'|' -)"
expect "package.sh signs before it verifies" "$package_order" 'sign_for_release "$APP"|codesign --verify --deep'
expect "verify-update.sh has no ad-hoc identity of its own" "$(grep -c -e '--sign -' scripts/verify-update.sh || true)" "0"

((failed == 0)) || die "FAIL"
echo "PASS: ad hoc and Team ID signing"
