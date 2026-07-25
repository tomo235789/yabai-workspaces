# ywr — yabai workspaces

English | [日本語](README.ja.md)

**Save your macOS window layout and put it back with one command** — across
displays and virtual desktops. Works with [yabai](https://github.com/koekeishiya/yabai)
for full Space/Display restore, and falls back to a built-in, yabai-independent
backend when yabai can't run.

<p align="center">
  <img src="docs/images/menubar.png" alt="ywr menu-bar app" width="320">
</p>

---

## Why

Multi-monitor setups scramble your windows every time you dock, undock, or
change displays. `ywr` captures where everything is and restores it — window
positions, sizes, the Space/Display each window lives on, and which window was
frontmost.

## How it works

`ywr` picks a backend automatically based on your setup:

```mermaid
flowchart TD
    A["ywr snapshot save / restore"] --> B{"yabai answering?<br/>(needs 'Displays have separate Spaces' ON)"}
    B -->|Yes| C["<b>yabai backend</b><br/>full restore:<br/>position + size<br/>+ Space + Display"]
    B -->|"No, or --native"| D["<b>native backend</b><br/>macOS Accessibility<br/>geometry-only:<br/>position + size<br/>+ across displays"]
```

- **yabai backend** — the full experience: also moves windows to the right
  Space and Display. Needs yabai running (which requires *Displays have separate
  Spaces* = ON) plus the scripting-addition for cross-Space moves.
- **native backend** — no yabai required. Restores window position/size
  (including moving across monitors) and the frontmost window, using the macOS
  Accessibility API. This is what makes ywr work in the "spanning desktop"
  configuration where yabai refuses to start.

## Quick start

```sh
# 1. (optional) install yabai for full Space/Display restore. Cross-Space moves
#    also require its scripting-addition — see the yabai wiki. Without yabai,
#    ywr uses the native backend (position/size + display, no Space moves).
brew install koekeishiya/formulae/yabai && yabai --start-service

# 2. build ywr and put it on your PATH
swift build -c release && mkdir -p ~/.local/bin && cp .build/release/ywr ~/.local/bin/ywr

# 3. check your environment (shows which backend is active)
ywr doctor

# 4. save the current layout, then restore it later
ywr snapshot save home
ywr restore home            # preview first with: ywr restore home --dry-run
```

Permissions differ by backend: the **native backend** needs **Accessibility**
granted to whatever runs `ywr` (Terminal, etc.); the **yabai backend** instead
needs **yabai itself** to have Accessibility, plus its scripting-addition for
cross-Space moves — `ywr` only shells out to `yabai -m`.

## What restore does

```mermaid
flowchart LR
    subgraph Save["ywr snapshot save"]
      direction TB
      S1["read live windows"] --> S2["snapshot.json<br/>~/.config/yabai-workspaces"]
    end
    subgraph Restore["ywr restore"]
      direction TB
      R1["read snapshot"] --> R2["match saved ↔ live<br/>by app + title + size"] --> R3["move · resize · focus<br/>(Space/Display if available)"]
    end
    Save -.-> Restore
```

Restore matches each saved window to a live one, then repositions it. Windows
it can't place are listed at the end — nothing fails silently.

## Backends at a glance

| Capability | yabai backend | native backend |
|---|:---:|:---:|
| Window position & size | ✅ | ✅ |
| Move across displays | ✅ | ✅ |
| Restore frontmost window | ✅ | ✅ |
| Move to the saved **Space** | ✅ | ❌ |
| Works with *separate Spaces* OFF | ❌ (yabai won't run) | ✅ |
| Extra requirement | yabai + scripting-addition | Accessibility (+ Screen Recording helps) |

Force the native backend anytime with `--native`
(e.g. `ywr restore home --native`).

## Auto-restore

Restore automatically when your displays change — pick whichever you like.
**These require the yabai backend** (they use yabai's display info/events and
are not available in the native, yabai-less setup):

```sh
ywr restore --auto        # pick the snapshot matching the current displays
ywr daemon                # watch for display changes and auto-restore (polling)
ywr signal install        # let yabai fire restore on display events (no daemon)
```

Without yabai, restore an explicit snapshot by name: `ywr restore home --native`.

## Menu-bar app

`ywr-menubar` mirrors the CLI in a SwiftUI menu-bar popover: type a name to
save, click a saved layout to restore it, or hit **Restore (auto)**. Colors and
fonts come from an external `theme.json`.

```sh
swift run ywr-menubar
```

> Like the CLI, the menu-bar app falls back to the **native backend** when yabai
> isn't running (save and click-to-restore work; **Restore (auto)** needs yabai).

## Documentation

- **[Usage guide](docs/usage.md)** — every command, the native backend, theming, troubleshooting ([日本語](docs/usage.ja.md))
- **[Roadmap](ROADMAP.md)** · **[PRD](PRD.md)**

## Architecture

A testable core (`YWRCore`) with thin executables around it. Every side effect
(yabai, Accessibility, the filesystem) sits behind a protocol, so the whole core
is unit-tested with in-memory fakes.

```mermaid
flowchart TD
    CLI["ywr<br/>(CLI)"] --> Core["YWRCore<br/>capture · plan · restore · match"]
    Menu["ywr-menubar<br/>(SwiftUI app)"] --> Core
    Menu --> UI["YWRMenuUI"]
    Menu --> Theme["YWRTheme"]
    Shot["ywr-shot<br/>(screenshots)"] --> UI
    Core --> Yabai["yabai backend<br/>YabaiClient"]
    Core --> Native["native backend<br/>CGWindowList + AX"]
```

```sh
swift build                # build the ywr binary
swift test                 # unit tests (XCTest; needs Xcode)
bash Tests/e2e/run.sh      # end-to-end: real binary vs. a fake yabai
bash scripts/report.sh     # → build/report/report.html (results + UI screenshots)
```

## License

MIT — see [LICENSE](LICENSE). yabai is a separate MIT-licensed project; ywr does
not include yabai binaries or source.
