#!/bin/bash
# End-to-end tests for ywr: build the real binary, put a fake `yabai` on PATH,
# run actual `ywr` commands, and assert on stdout, exit codes, saved JSON, and
# the control commands ywr sent to yabai.
#
# This is the CLI analogue of a Playwright browser test: the app runs as a real
# process against a controlled backend, and we assert on observable behavior.
#
# Usage: bash Tests/e2e/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# --- build the real ywr binary -------------------------------------------------
echo "▶ building ywr…"
swift build --package-path "$ROOT" >/dev/null
YWR="$(swift build --package-path "$ROOT" --show-bin-path)/ywr"
[[ -x "$YWR" ]] || { echo "ywr binary not found at $YWR"; exit 1; }

# --- sandbox: fake yabai on PATH, temp config dir ------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/fixtures" "$WORK/cfg"
cp "$HERE/fake-yabai" "$WORK/bin/yabai"
chmod +x "$WORK/bin/yabai"

export YWR_E2E_FIXTURES="$WORK/fixtures"
export YWR_E2E_YABAI_LOG="$WORK/yabai.log"
: > "$YWR_E2E_YABAI_LOG"
export PATH="$WORK/bin:$PATH"
export XDG_CONFIG_HOME="$WORK/cfg"

cat > "$WORK/fixtures/displays.json" <<'JSON'
[{"id":1,"uuid":"AAA","index":1,"frame":{"x":0,"y":0,"w":1728,"h":1117},"spaces":[1,2],"has-focus":true},
 {"id":2,"uuid":"BBB","index":2,"frame":{"x":1728,"y":0,"w":3840,"h":2160},"spaces":[3],"has-focus":false}]
JSON
cat > "$WORK/fixtures/spaces.json" <<'JSON'
[{"id":1,"index":1,"label":"code","display":1,"windows":[10],"has-focus":true,"is-native-fullscreen":false},
 {"id":3,"index":3,"label":"web","display":2,"windows":[20],"has-focus":false,"is-native-fullscreen":false}]
JSON
cat > "$WORK/fixtures/windows.json" <<'JSON'
[{"id":10,"pid":111,"app":"Code","title":"project","frame":{"x":50,"y":60,"w":800,"h":900},"role":"AXWindow","subrole":"AXStandardWindow","display":1,"space":1,"is-visible":true,"is-floating":true,"is-sticky":false,"is-minimized":false,"is-native-fullscreen":false,"has-focus":true},
 {"id":20,"pid":222,"app":"Safari","title":"docs","frame":{"x":1800,"y":100,"w":2000,"h":1800},"role":"AXWindow","subrole":"AXStandardWindow","display":2,"space":3,"is-visible":true,"is-floating":false,"is-sticky":false,"is-minimized":false,"is-native-fullscreen":false,"has-focus":false}]
JSON

# --- tiny assertion harness ----------------------------------------------------
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
assert_contains() { if grep -qF -e "$2" <<<"$1"; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
assert_absent()   { if grep -qF -e "$2" <<<"$1"; then bad "$3 (unexpected: $2)"; else ok "$3"; fi; }
assert_eq()       { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
assert_file()     { if [[ -f "$1" ]]; then ok "$2"; else bad "$2 (no file $1)"; fi; }

echo "▶ running e2e assertions…"

# doctor passes when yabai answers
out="$("$YWR" doctor)"; code=$?
assert_eq "$code" "0" "doctor exits 0 with yabai present"
assert_contains "$out" "responded with 2 display(s)" "doctor sees 2 displays"

# snapshot save writes JSON with the right fingerprint
out="$("$YWR" snapshot save home)"
assert_contains "$out" "2 window(s), 2 space(s)" "snapshot save reports counts"
assert_file "$XDG_CONFIG_HOME/yabai-workspaces/snapshots/home.json" "snapshot JSON written"
assert_contains "$(cat "$XDG_CONFIG_HOME/yabai-workspaces/snapshots/home.json")" "1728x1117+3840x2160" "snapshot has fingerprint"

# list shows it
assert_contains "$("$YWR" snapshot list)" "home" "snapshot list shows home"

# dry-run must not touch yabai
: > "$YWR_E2E_YABAI_LOG"
out="$("$YWR" restore home --dry-run)"
assert_contains "$out" "No changes made (dry run)." "dry-run makes no changes"
assert_eq "$(wc -l < "$YWR_E2E_YABAI_LOG" | tr -d ' ')" "0" "dry-run sent no control ops"

# real restore issues window moves
: > "$YWR_E2E_YABAI_LOG"
"$YWR" restore home >/dev/null 2>&1
log="$(cat "$YWR_E2E_YABAI_LOG")"
assert_contains "$log" "window 10 --display" "restore moves window to display"
assert_contains "$log" "window 10 --space" "restore moves window to space"
assert_contains "$log" "--focus" "restore refocuses a window"

# positions-only restore skips ALL display/space moves but still sets geometry
: > "$YWR_E2E_YABAI_LOG"
"$YWR" restore home --positions-only >/dev/null 2>&1
log="$(cat "$YWR_E2E_YABAI_LOG")"
assert_absent "$log" "--display" "positions-only sends no display moves (any window)"
assert_absent "$log" "--space " "positions-only sends no space moves (any window)"
assert_contains "$log" "window 10 --move" "positions-only restores floating window 10 geometry"

# profile capture
out="$("$YWR" profile capture home)"
assert_contains "$out" "2 display(s)" "profile capture reports displays"
assert_file "$XDG_CONFIG_HOME/yabai-workspaces/profiles/home.json" "profile JSON written"

# restore --auto picks the matching snapshot
assert_contains "$("$YWR" restore --auto --dry-run)" "Auto-selected 'home'" "restore --auto selects home"

# signal install/uninstall drive yabai signal add/remove
: > "$YWR_E2E_YABAI_LOG"
"$YWR" signal install >/dev/null
assert_eq "$(grep -c -- '--add' "$YWR_E2E_YABAI_LOG")" "3" "signal install adds 3 signals"
: > "$YWR_E2E_YABAI_LOG"
"$YWR" signal uninstall >/dev/null
assert_eq "$(grep -c -- '--remove' "$YWR_E2E_YABAI_LOG")" "3" "signal uninstall removes 3 signals"

# unknown command fails
"$YWR" bogus >/dev/null 2>&1; assert_eq "$?" "1" "unknown command exits non-zero"

echo
echo "e2e: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
