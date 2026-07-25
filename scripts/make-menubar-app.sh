#!/bin/bash
# Package the ywr-menubar executable into a proper macOS .app bundle so the
# menu-bar icon reliably appears and it can be launched by double-click / `open`.
# The Info.plist marks it LSUIElement (menu-bar accessory, no Dock icon).
#
# Usage: bash scripts/make-menubar-app.sh
# Result: build/YabaiWorkspaces.app  ->  open build/YabaiWorkspaces.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/build/YabaiWorkspaces.app"
MACOS="${APP}/Contents/MacOS"

echo "building ywr-menubar (release)..."
swift build --package-path "${ROOT}" -c release --product ywr-menubar >/dev/null
BIN="$(swift build --package-path "${ROOT}" -c release --show-bin-path)/ywr-menubar"

echo "assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${MACOS}"
cp "${BIN}" "${MACOS}/ywr-menubar"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>yabai workspaces</string>
    <key>CFBundleDisplayName</key>     <string>yabai workspaces</string>
    <key>CFBundleIdentifier</key>      <string>com.tomo235789.yabai-workspaces</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleExecutable</key>      <string>ywr-menubar</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign the bundle. An UNSIGNED bundle is the worst case for TCC:
# macOS can't form a stable identity for it, so an Accessibility grant often
# doesn't actually take effect (the toggle shows on but AX calls silently fail).
# Ad-hoc signing gives a stable designated requirement keyed on the bundle id,
# so the grant sticks and window moves work.
echo "codesigning (ad-hoc) ..."
codesign --force --deep --sign - "${APP}"

echo "built ${APP}"
echo "  launch it with:  open \"${APP}\""
echo
echo "  First run needs Accessibility permission for 'yabai workspaces':"
echo "    System Settings ▸ Privacy & Security ▸ Accessibility"
echo "  If it was granted before this rebuild, REMOVE the old 'yabai workspaces'"
echo "  entry (−) and re-add it — a rebuild invalidates the previous grant."
echo "  (Optional) also grant Screen Recording so window titles are captured,"
echo "  which improves matching when an app has several windows."
