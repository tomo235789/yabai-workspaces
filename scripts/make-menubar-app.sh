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

# App icon (generate once with scripts/make-icon.sh; committed under Resources/).
if [ -f "${ROOT}/Resources/AppIcon.icns" ]; then
    mkdir -p "${APP}/Contents/Resources"
    cp "${ROOT}/Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>yabai workspaces</string>
    <key>CFBundleDisplayName</key>     <string>yabai workspaces</string>
    <key>CFBundleIdentifier</key>      <string>com.tomo235789.yabai-workspaces</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleExecutable</key>      <string>ywr-menubar</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Single-source the version: read it from YWRVersion (Sources/YWRCore/Version.swift)
# so a release only bumps one file.
VERSION="$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' "${ROOT}/Sources/YWRCore/Version.swift" | tr -d '"' | head -1)"
if [ -n "${VERSION}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP}/Contents/Info.plist"
fi

# Codesign the bundle. Prefer a STABLE self-signed identity (if created via
# scripts/create-signing-cert.sh): it keys the designated requirement on the
# certificate, so TCC keeps the Accessibility / Screen Recording grant across
# rebuilds. Without it, fall back to ad-hoc — which works but changes identity on
# every rebuild, so the grant must be re-added each time.
SIGN_IDENTITY="${YWR_SIGN_IDENTITY:-ywr-selfsigned}"
STABLE_SIGNED=0
# `find-identity -p codesigning` lists identities that have BOTH a certificate
# and its private key (even self-signed / untrusted ones), so a cert-only import
# won't be mistaken for a usable identity. Column 2 is the cert's SHA-1 hash.
# `|| true` so a no-match (grep exit 1) under `set -eo pipefail` leaves the hash
# empty and falls through to ad-hoc signing instead of aborting the build.
# Match the quoted CN exactly ("name") so a prefix like ywr-selfsigned can't
# pick up ywr-selfsigned-old and sign with the wrong certificate.
IDENTITY_HASH="$(security find-identity -p codesigning 2>/dev/null | grep -F "\"${SIGN_IDENTITY}\"" | head -1 | awk '{print $2}' || true)"
# `|| true` so a PlistBuddy failure under `set -e` doesn't abort before the
# ad-hoc fallback (an empty BUNDLE_ID just skips the stable-signing branch).
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist" 2>/dev/null || true)"
if [[ -n "${IDENTITY_HASH}" && -n "${BUNDLE_ID}" ]]; then
    # Pin the designated requirement to the bundle id + this certificate leaf, so
    # it never relies on system trust of the self-signed cert (no "anchor trusted"
    # to satisfy). TCC then keeps the grant across rebuilds as long as the same
    # certificate signs the app. Fall back to ad-hoc if signing fails for any
    # reason rather than aborting the build.
    REQ="=designated => identifier \"${BUNDLE_ID}\" and certificate leaf = H\"${IDENTITY_HASH}\""
    if codesign --force --deep --sign "${IDENTITY_HASH}" -r "${REQ}" "${APP}" 2>/dev/null; then
        echo "codesigned with stable identity '${SIGN_IDENTITY}' (grants persist across rebuilds)."
        STABLE_SIGNED=1
    fi
fi
if [[ "${STABLE_SIGNED}" -eq 0 ]]; then
    echo "codesigning (ad-hoc) ..."
    codesign --force --deep --sign - "${APP}"
fi

echo "built ${APP}"
echo "  launch it with:  open \"${APP}\""
echo
echo "  First run needs Accessibility permission for 'yabai workspaces':"
echo "    System Settings ▸ Privacy & Security ▸ Accessibility"
if [[ "${STABLE_SIGNED}" -eq 1 ]]; then
    echo "  (Grant it once; the stable signature keeps the grant across rebuilds.)"
else
    echo "  If it was granted before this rebuild, REMOVE the old 'yabai workspaces'"
    echo "  entry (−) and re-add it — an ad-hoc rebuild invalidates the previous grant."
    echo "  Tip: run 'bash scripts/create-signing-cert.sh' once to stop this recurring."
fi
echo "  (Optional) also grant Screen Recording so window titles are captured,"
echo "  which improves matching when an app has several windows."
