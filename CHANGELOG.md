# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — first public preview

### Added

- **Save & restore window layouts** as named snapshots (`ywr snapshot save`,
  `ywr restore`), with a `--dry-run` preview.
- **Two backends**: yabai (full Space/Display restore) and a built-in,
  yabai-independent **native backend** (macOS Accessibility / CoreGraphics) that
  restores window position/size, works in the "spanning" display setup where
  yabai can't run.
- **Restore across all desktops** (`restore --native --walk-spaces`) — walks
  Spaces to place windows on every desktop, then returns you home.
- **Menu-bar app**: save, click-to-restore, ▦ restore-across-desktops, 🔄
  overwrite, 🗑 delete (with confirmation); themed via an external `theme.json`.
- **Snapshot management**: `snapshot list`, `snapshot delete`.
- **Display profiles**: `profile capture`, `profile list`.
- **Doctor**: `ywr doctor` checks the environment and active backend.
- **`ywr --version`**.
- Stable self-signed local code signing so the Accessibility grant survives
  rebuilds (`scripts/create-signing-cert.sh`), login auto-start
  (`scripts/autostart-install.sh`), and a Developer ID notarization pipeline for
  distribution (`scripts/release.sh`).

### Removed

- Automatic restore on display changes (`restore --auto`, `daemon`, `signal`) —
  the tool is now explicit save/restore only. Any previously installed yabai
  signals are cleaned up automatically on first run.

[Unreleased]: https://github.com/tomo235789/yabai-workspaces/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tomo235789/yabai-workspaces/releases/tag/v0.1.0
