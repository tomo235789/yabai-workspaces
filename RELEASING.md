# Releasing

ywr ships two things: the **CLI** (`ywr`, built from source / Homebrew) and the
**menu-bar app** (`YabaiWorkspaces.app`, distributed as a signed + notarized
build attached to a GitHub Release).

CI (`.github/workflows/ci.yml`) builds, tests, and lints every push/PR.
CD (`.github/workflows/release.yml`) publishes a signed, notarized app whenever a
`v*` tag is pushed.

## Cutting a release

1. **Bump the version** in one place — `Sources/YWRCore/Version.swift`
   (`YWRVersion.current`). The app bundle reads it automatically, and the release
   workflow refuses to run if the tag doesn't match.
2. **Update `CHANGELOG.md`** — move items from `Unreleased` into a new
   `## [x.y.z]` section.
3. Commit, then **tag and push**:
   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```
4. The **Release** workflow builds → Developer ID-signs (hardened runtime) →
   notarizes → staples → creates a GitHub Release with
   `YabaiWorkspaces.zip` attached.

To build + notarize locally instead, see `scripts/release.sh`.

## Required GitHub repository secrets

Set these under **Settings ▸ Secrets and variables ▸ Actions**:

| Secret | What it is |
|---|---|
| `SIGNING_CERTIFICATE_P12_BASE64` | Your **Developer ID Application** cert + private key, exported as a `.p12` and base64-encoded |
| `SIGNING_CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` |
| `SIGNING_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` | Apple ID email used for notarization |
| `NOTARY_TEAM_ID` | Your Apple Developer Team ID |
| `NOTARY_PASSWORD` | An **app-specific password** for that Apple ID |

### Exporting the certificate for `SIGNING_CERTIFICATE_P12_BASE64`

1. In **Keychain Access**, find your *Developer ID Application* certificate,
   expand it to include the private key, select both, right-click ▸ **Export**,
   and save a `.p12` (set a password → that's `SIGNING_CERTIFICATE_PASSWORD`).
2. Base64-encode it for the secret:
   ```sh
   base64 -i DeveloperID.p12 | pbcopy   # paste into SIGNING_CERTIFICATE_P12_BASE64
   ```

### App-specific password for `NOTARY_PASSWORD`

Create one at <https://appleid.apple.com> ▸ Sign-In & Security ▸ App-Specific
Passwords. (This is different from your Apple ID password.)

## Prerequisites (one-time)

- Enroll in the **Apple Developer Program** and create a **Developer ID
  Application** certificate.
- The Mac App Store is **not** an option — ywr uses private/Accessibility APIs.
  Distribution is direct download (GitHub Releases) and, later, a Homebrew Cask.
