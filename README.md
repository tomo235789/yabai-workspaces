# ywr — yabai workspaces

English | [日本語](README.ja.md)

Save your macOS window layout (displays, Spaces, window placement) as a named
snapshot and restore it when the same display configuration comes back. `ywr` is
a thin **companion CLI** for [yabai](https://github.com/koekeishiya/yabai) — it
does not fork or bundle yabai; it shells out to `yabai -m`.

## Status

Implemented:

- **CLI (`ywr`)**: `doctor`, `snapshot save/list`, `restore` (with `--dry-run`
  and `--auto`), `profile capture/list`, and `daemon` (watch for display changes
  and auto-restore).
- **Menu-bar app (`ywr-menubar`)**: a SwiftUI `MenuBarExtra` to save the current
  layout and trigger auto-restore, themed from an external file.

## Documentation

- **[Usage guide](docs/usage.md)** — install, core workflow, auto-restore, theming, troubleshooting ([日本語](docs/usage.ja.md))

## Requirements

This tool requires yabai to be installed and configured separately.

```sh
brew install koekeishiya/formulae/yabai
yabai --start-service
```

Run `ywr doctor` to verify your environment.

## Usage

```sh
ywr doctor                 # check yabai + environment
ywr snapshot save home     # capture the current layout as "home"
ywr snapshot list          # list saved snapshots
ywr restore home --dry-run # preview what restore would do
ywr restore home           # move windows back into place
ywr restore --auto         # pick the snapshot matching the current displays
ywr restore home --create-spaces  # also create missing labeled Spaces first
ywr profile capture home   # record the current display configuration
ywr daemon --interval 2    # auto-restore whenever the displays change (polling)
ywr signal install         # let yabai auto-restore on display events (no daemon)
```

`ywr daemon` (polling) and `ywr signal install` (event-driven via yabai signals)
are two ways to trigger auto-restore automatically — use whichever you prefer.
Restoring also brings back each window's floating / minimized / fullscreen state
and refocuses the window that was active at capture time.

Snapshots and profiles are stored as JSON under `$XDG_CONFIG_HOME/yabai-workspaces`
(default `~/.config/yabai-workspaces`).

### Theming the menu-bar app

Colors and fonts live in a separate JSON file so they can be changed without
touching code. Drop a `theme.json` next to your snapshots
(`~/.config/yabai-workspaces/theme.json`); if absent, a built-in dark default is
used. Schema:

```json
{
  "colors": {
    "accent": "#4C8DFF", "background": "#1E1E1E", "surface": "#2A2A2A",
    "textPrimary": "#FFFFFF", "textSecondary": "#A0A0A0",
    "success": "#3FB950", "warning": "#D29922", "error": "#F85149"
  },
  "font": { "family": "System", "regularSize": 13, "titleSize": 15, "monospacedDigits": true }
}
```

## Build & test

```sh
swift build                # builds the `ywr` binary
swift test                 # unit tests — XCTest suite (requires Xcode)
bash Tests/e2e/run.sh      # end-to-end: runs the real binary against a fake yabai
bash scripts/report.sh     # → build/report/report.html (results + UI screenshots)
```

`scripts/report.sh` runs the unit and e2e suites and renders the menu-bar UI to
PNGs (headlessly, via `ImageRenderer`), then assembles a single self-contained
`build/report/report.html` with the results and embedded screenshots.

The e2e suite (`Tests/e2e/`) drives the actual `ywr` binary as a black box
against a fake `yabai` on `PATH` — the CLI analogue of a Playwright browser
test — asserting on stdout, exit codes, saved JSON, and the control commands
ywr sends to yabai.

## Architecture

The code is split into a testable core library (`YWRCore`) and a thin CLI
(`ywr`) that is nothing more than a composition root plus argument dispatch.
The design leans on SOLID:

- **Single Responsibility** — one type per job: `SnapshotCapturer` (read state →
  snapshot), `RestorePlanner` (snapshot + live state → plan), `SnapshotRestorer`
  (execute a plan), `DisplayMatcher` (score displays), `FileSnapshotStore`
  (persist), `Doctor` (diagnose).
- **Open/Closed** — new behavior slots in without editing dispatchers: CLI
  verbs conform to `Command` and register in `CommandRegistry`; environment
  checks conform to `DiagnosticCheck`; scoring is driven by `MatchWeights` data.
- **Liskov** — every collaborator is used only through its protocol, and the
  in-memory fakes in the test suite substitute for the real ones transparently.
- **Interface Segregation** — yabai access is split into `YabaiQuerying` (reads)
  and `YabaiControlling` (mutations) so capture/doctor can't touch state.
- **Dependency Inversion** — all side effects funnel through the `CommandRunner`
  abstraction; the entire core is unit-tested without a real machine or yabai.

The restore path deliberately **separates planning from execution**: the planner
is a pure function (so `--dry-run` is exact and everything is testable), and the
executor applies the plan and reports every window's outcome — no failure is
swallowed silently.

## License

This project is licensed under the MIT License. See `LICENSE`.

yabai is a separate project licensed under the MIT License.
This project does not include yabai binaries or source code.
