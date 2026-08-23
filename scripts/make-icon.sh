#!/bin/bash
# Generate Resources/AppIcon.icns from scripts/make-icon.swift. Run this only
# when changing the icon; the committed .icns is what make-menubar-app.sh bundles.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
MASTER="${TMP}/icon-1024.png"
ICONSET="${TMP}/AppIcon.iconset"

echo "rendering master PNG ..."
swiftc -O -o "${TMP}/draw" "${ROOT}/scripts/make-icon.swift"
"${TMP}/draw" "${MASTER}" >/dev/null

echo "building iconset ..."
mkdir -p "${ICONSET}"
for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z "${s}" "${s}" "${MASTER}" --out "${ICONSET}/icon_${s}x${s}.png"    >/dev/null
    sips -z "${d}" "${d}" "${MASTER}" --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
done

mkdir -p "${OUT_DIR}"
iconutil -c icns "${ICONSET}" -o "${OUT_DIR}/AppIcon.icns"
echo "wrote ${OUT_DIR}/AppIcon.icns"
