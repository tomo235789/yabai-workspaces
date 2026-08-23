#!/bin/bash
# Build, Developer ID-sign, notarize, and staple the menu-bar app for PUBLIC
# distribution. Produces a notarized build/YabaiWorkspaces.app plus a
# ready-to-share build/YabaiWorkspaces.zip.
#
# This is separate from scripts/make-menubar-app.sh (which self-signs for local
# use): notarization requires a real Developer ID certificate + hardened runtime.
#
# --- One-time setup (needs an Apple Developer account) ---
#   1. Join the Apple Developer Program and create a "Developer ID Application"
#      certificate; install it in your login keychain.
#   2. Store notarization credentials once (uses an app-specific password):
#        xcrun notarytool store-credentials ywr-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "<app-specific-pw>"
#
# --- Required env ---
#   YWR_DEVELOPER_ID    e.g. "Developer ID Application: Your Name (TEAMID)"
#   Notarization credentials — EITHER:
#     YWR_NOTARY_PROFILE  the notarytool keychain profile name (local use), OR
#     YWR_NOTARY_APPLE_ID + YWR_NOTARY_TEAM_ID + YWR_NOTARY_PASSWORD  (CI)
# --- Optional env ---
#   YWR_ENTITLEMENTS    path to an entitlements plist (usually not needed:
#                       Accessibility / event posting are TCC-gated, not entitlements)
#
# Usage: bash scripts/release.sh
set -euo pipefail

: "${YWR_DEVELOPER_ID:?set YWR_DEVELOPER_ID to your \"Developer ID Application: … (TEAMID)\" identity}"

# Notarization credentials: either a stored keychain profile (local use), or
# direct App Store Connect credentials (CI, where no profile exists).
NOTARY_ARGS=()
if [ -n "${YWR_NOTARY_PROFILE:-}" ]; then
    NOTARY_ARGS=(--keychain-profile "${YWR_NOTARY_PROFILE}")
elif [ -n "${YWR_NOTARY_APPLE_ID:-}" ] && [ -n "${YWR_NOTARY_TEAM_ID:-}" ] && [ -n "${YWR_NOTARY_PASSWORD:-}" ]; then
    NOTARY_ARGS=(--apple-id "${YWR_NOTARY_APPLE_ID}" --team-id "${YWR_NOTARY_TEAM_ID}" --password "${YWR_NOTARY_PASSWORD}")
else
    echo "error: set YWR_NOTARY_PROFILE, or YWR_NOTARY_APPLE_ID + YWR_NOTARY_TEAM_ID + YWR_NOTARY_PASSWORD" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/build/YabaiWorkspaces.app"
ZIP="${ROOT}/build/YabaiWorkspaces.zip"

# 1) Assemble the bundle with the standard packager (self-signs; re-signed below).
echo "==> assembling bundle"
bash "${ROOT}/scripts/make-menubar-app.sh" >/dev/null

# 2) Re-sign with Developer ID + hardened runtime + secure timestamp (all three
#    are required for notarization). --force replaces the local dev signature.
echo "==> signing with '${YWR_DEVELOPER_ID}' (hardened runtime)"
SIGN_ARGS=(--force --deep --options runtime --timestamp --sign "${YWR_DEVELOPER_ID}")
if [ -n "${YWR_ENTITLEMENTS:-}" ]; then
    SIGN_ARGS+=(--entitlements "${YWR_ENTITLEMENTS}")
fi
codesign "${SIGN_ARGS[@]}" "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"

# 3) Zip for submission (ditto preserves the bundle structure/signature).
rm -f "${ZIP}"
/usr/bin/ditto -c -k --keepParent "${APP}" "${ZIP}"

# 4) Notarize and block until Apple returns a result.
echo "==> submitting for notarization (this can take a few minutes)"
xcrun notarytool submit "${ZIP}" "${NOTARY_ARGS[@]}" --wait

# 5) Staple the ticket onto the app, then re-zip the stapled app to distribute.
echo "==> stapling"
xcrun stapler staple "${APP}"
rm -f "${ZIP}"
/usr/bin/ditto -c -k --keepParent "${APP}" "${ZIP}"

# 6) Confirm Gatekeeper will accept it on a clean machine.
echo "==> Gatekeeper check"
spctl -a -vvv -t install "${APP}" || true

echo
echo "done:"
echo "  notarized app → ${APP}"
echo "  distributable → ${ZIP}  (upload to GitHub Releases / Homebrew Cask)"
