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

echo "built ${APP}"
echo "  launch it with:  open \"${APP}\""
echo "  (grant Accessibility permission to 'yabai workspaces' the first time)"
