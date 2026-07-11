#!/bin/bash
# Runs the full verification suite (unit tests, end-to-end tests, and UI
# screenshot rendering) and produces a single self-contained HTML report at
# build/report/report.html with embedded screenshots.
#
# Usage: bash scripts/report.sh [output-dir]
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/report}"
IMG="$OUT/img"
mkdir -p "$IMG"

# Prefer Xcode's toolchain so XCTest is available.
if [[ -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "▶ building…"
swift build --package-path "$ROOT" >/dev/null 2>&1

echo "▶ unit tests…"
swift test --package-path "$ROOT" > "$OUT/unit.log" 2>&1
UNIT_RC=$?

echo "▶ end-to-end tests…"
bash "$ROOT/Tests/e2e/run.sh" > "$OUT/e2e.log" 2>&1
E2E_RC=$?

echo "▶ rendering UI screenshots…"
SHOT="$(swift build --package-path "$ROOT" --show-bin-path 2>/dev/null)/ywr-shot"
if [[ -x "$SHOT" ]]; then
  "$SHOT" "$IMG" > "$OUT/shot.log" 2>&1
  SHOT_RC=$?
else
  echo "ywr-shot binary not found at $SHOT" > "$OUT/shot.log"
  SHOT_RC=1
fi

echo "▶ assembling HTML…"
UNIT_RC=$UNIT_RC E2E_RC=$E2E_RC SHOT_RC=$SHOT_RC OUT="$OUT" IMG="$IMG" python3 "$ROOT/scripts/gen_report.py"

echo "✓ report: $OUT/report.html"
