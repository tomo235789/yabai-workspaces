# ywr — yabai workspaces

Save your macOS window layout (displays, Spaces, window placement) as a named
snapshot and restore it when the same display configuration comes back. `ywr` is
a thin **companion CLI** for [yabai](https://github.com/koekeishiya/yabai) — it
does not fork or bundle yabai; it shells out to `yabai -m`.

## Status

Implemented: `doctor`, `snapshot save`, `snapshot list`, `restore` (with
`--dry-run` and `--auto`), `profile capture`, `profile list`. A background daemon
(display-change auto-restore) and a menu-bar app are planned (see `plans.md` /
`PRD.md`).

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
```

Snapshots are stored as JSON under `$XDG_CONFIG_HOME/yabai-workspaces`
(default `~/.config/yabai-workspaces`).

## Build & test

```sh
swift build                # builds the `ywr` binary
swift run ywr-tests        # runs the unit suite (no Xcode required)
```

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
