#!/bin/bash
# Disable login auto-start installed by scripts/autostart-install.sh.
# Removes the LaunchAgent and stops the running app; leaves the installed bundle
# at ~/Applications/YabaiWorkspaces.app (delete it manually if you want).
set -euo pipefail

LABEL="com.tomo235789.yabai-workspaces"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
rm -f "${PLIST}"
# -x matches the exact process name, so a shell/editor whose command line merely
# contains "ywr-menubar" is not killed.
pkill -x ywr-menubar 2>/dev/null || true

echo "auto-start disabled (LaunchAgent removed, app stopped)."
echo "the app bundle is kept at ~/Applications/YabaiWorkspaces.app"
