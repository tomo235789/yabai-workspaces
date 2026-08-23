#!/bin/bash
# Install the menu-bar app to ~/Applications and start it automatically at every
# login via a per-user LaunchAgent.
#
# A LaunchAgent (rather than a Login Item) is used because it installs without an
# Automation-permission prompt. Copying the bundle to a stable location preserves
# its code signature, so the Accessibility grant keeps working across rebuilds.
#
# Usage:   bash scripts/autostart-install.sh
# Disable: bash scripts/autostart-uninstall.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/build/YabaiWorkspaces.app"
DEST_DIR="${HOME}/Applications"
DEST="${DEST_DIR}/YabaiWorkspaces.app"
LABEL="com.tomo235789.yabai-workspaces"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

# Always (re)build so a rerun refreshes the installed copy with the current
# source and signature (stable-signed if the cert exists).
bash "${ROOT}/scripts/make-menubar-app.sh"

# Stop any running instance first, so `open` below launches the freshly-copied
# binary instead of just re-activating the old one. -x matches the exact process
# name (not any command line that merely contains it).
pkill -x ywr-menubar 2>/dev/null || true

# Install a copy to a stable path. cp -R preserves the code signature, so TCC —
# which keys on the bundle id + certificate, not the path — keeps the grant.
echo "installing app to ${DEST} ..."
mkdir -p "${DEST_DIR}"
rm -rf "${DEST}"
cp -R "${SRC}" "${DEST}"

# LaunchAgent: at login, `open` the app once; it then lives in the menu bar.
echo "writing LaunchAgent ${PLIST} ..."
mkdir -p "${HOME}/Library/LaunchAgents"
cat > "${PLIST}" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>${DEST}</string>
    </array>
    <key>RunAtLoad</key>        <true/>
</dict>
</plist>
PLIST_EOF

# (Re)load the agent so it's active now and at every login.
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST}"

echo "starting it now ..."
open "${DEST}"

echo
echo "done — 'yabai workspaces' will start at every login."
echo "  app   → ${DEST}"
echo "  agent → ${PLIST}"
echo "disable auto-start with: bash scripts/autostart-uninstall.sh"
