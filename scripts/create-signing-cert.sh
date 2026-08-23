#!/bin/bash
# Create a stable, self-signed code-signing certificate in the login keychain.
#
# Why: an UNSIGNED or ad-hoc-signed bundle gets a new identity every rebuild, so
# macOS (TCC) drops the Accessibility / Screen Recording grants and you must
# re-add the app each time. Signing with a STABLE certificate makes the app's
# "designated requirement" constant across rebuilds
#   identifier "com.tomo235789.yabai-workspaces" and certificate leaf = H"<hash>"
# so a permission granted once keeps working after every rebuild.
#
# The certificate is self-signed and does NOT need to be trusted — codesign uses
# it by name and TCC keys on the cert leaf, not on system trust. Nothing here
# needs sudo; the login keychain is already unlocked in your session.
#
# Usage: bash scripts/create-signing-cert.sh
# Undo:  security delete-certificate -c ywr-selfsigned   (via Keychain Access to
#        also remove the private key)
set -euo pipefail

CERT_NAME="${YWR_SIGN_IDENTITY:-ywr-selfsigned}"

# Look for a usable IDENTITY (certificate + private key), not just a certificate:
# find-identity lists identities even when self-signed/untrusted, so a stale
# cert-only entry won't make us skip creating a working one.
# Match the quoted CN exactly ("name") so a prefix doesn't match a different
# identity (e.g. ywr-selfsigned vs ywr-selfsigned-old).
if security find-identity -p codesigning 2>/dev/null | grep -qF "\"${CERT_NAME}\""; then
    echo "signing identity '${CERT_NAME}' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# A code-signing leaf certificate (CA:FALSE + codeSigning EKU).
cat > "${TMP}/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${CERT_NAME}
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

if ! openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" \
    -days 3650 -config "${TMP}/openssl.cnf" 2>"${TMP}/req.err"; then
    echo "error: certificate generation failed:" >&2
    cat "${TMP}/req.err" >&2
    exit 1
fi

# Apple's Security framework only reads legacy PKCS#12 (SHA1 MAC / 3DES). OpenSSL
# 3 (e.g. Homebrew) disables those by default and needs -legacy; LibreSSL (the
# system openssl) has no -legacy flag but supports them natively. Add the flag
# only when this openssl advertises it, and surface any export error.
P12_PW="ywr-transient"
# String (not array) so an empty value expands to nothing under bash 3.2 + set -u;
# "-legacy" has no spaces, so the unquoted expansion below is safe.
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    LEGACY="-legacy"
fi
# shellcheck disable=SC2086
if ! openssl pkcs12 -export -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
    -out "${TMP}/id.p12" -passout "pass:${P12_PW}" -name "${CERT_NAME}" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES ${LEGACY} 2>"${TMP}/p12.err"; then
    echo "error: PKCS#12 export failed:" >&2
    cat "${TMP}/p12.err" >&2
    exit 1
fi

# Import into the LOGIN keychain specifically (default-keychain is not always the
# login keychain). -T /usr/bin/codesign pre-authorises codesign without a prompt.
LOGIN_KEYCHAIN="$(security login-keychain 2>/dev/null | tr -d ' "')"
[ -n "${LOGIN_KEYCHAIN}" ] || LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
security import "${TMP}/id.p12" -k "${LOGIN_KEYCHAIN}" -P "${P12_PW}" -T /usr/bin/codesign >/dev/null

echo "created code-signing certificate '${CERT_NAME}' in ${LOGIN_KEYCHAIN}"
echo "now rebuild the app: bash scripts/make-menubar-app.sh"
echo "grant Accessibility once more (the signature changed); after that, rebuilds keep the grant."
