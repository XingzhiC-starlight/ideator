#!/bin/bash
# Proves that the update-test feed server answers on this Mac's loopback addresses, IPv6 and IPv4, and
# on no other address. Needs no Xcode and no build.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

dir="$(mktemp -d)"
pid=""
cleanup() {
  [[ -z "$pid" ]] || { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; } || true
  rm -rf "$dir"
}
trap cleanup EXIT
die() { echo "test-feed-server: $*" >&2; exit 1; }

echo hello >"$dir/probe.txt"
port="$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
python3 -I scripts/verify-update/server.py "$port" "$dir" >"$dir/server.log" 2>&1 &
pid=$!
for _ in $(seq 50); do grep -q listening "$dir/server.log" && break; sleep 0.1; done
grep -q listening "$dir/server.log" || die "the server did not start: $(<"$dir/server.log")"

path=/releases/download/test/probe.txt
[[ "$(curl -sS --max-time 5 "http://127.0.0.1:$port$path")" == hello ]] || die "no answer on 127.0.0.1"
[[ "$(curl -sS --max-time 5 -g "http://[::1]:$port$path")" == hello ]] || die "no answer on ::1"
[[ "$(curl -sS --max-time 5 "http://localhost:$port/releases/latest/download/probe.txt" -L)" == hello ]] \
  || die "the latest/download redirect does not reach the file"
echo "answers: 127.0.0.1, ::1 and the latest/download redirect"

listening="$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN -Fn | sed -n 's/^n//p' | sort)"
[[ -n "$listening" ]] || die "lsof shows no listening socket for pid $pid"
while IFS= read -r address; do
  [[ "$address" == "127.0.0.1:$port" || "$address" == "[::1]:$port" ]] \
    || die "listening on $address; only 127.0.0.1 and ::1 may be (listeners: $(tr '\n' ' ' <<<"$listening"))"
done <<<"$listening"
echo "listening: $(tr '\n' ' ' <<<"$listening")"

lan="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
if [[ -n "$lan" ]]; then
  ! curl -sS --max-time 3 -o /dev/null "http://$lan:$port$path" 2>/dev/null || die "the server answers on $lan"
  echo "refused: $lan"
else
  echo "refused: no LAN address on this Mac to try"
fi
echo "PASS: the feed server is loopback only"
