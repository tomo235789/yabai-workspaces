# ywr Usage Guide

English | [日本語](usage.ja.md)

`ywr` (yabai-workspaces) saves your macOS window layout under a name and
restores it when the same display configuration returns. This guide walks from
install to daily use.

---

## 1. Prerequisite: yabai

`ywr` drives [yabai](https://github.com/koekeishiya/yabai). Install and start it
first:

```sh
brew install koekeishiya/formulae/yabai
yabai --start-service
```

macOS settings to check:

- **System Settings ▸ Desktop & Dock ▸ "Displays have separate Spaces" = ON**
- Grant yabai **Accessibility** permission
- Restoring across Spaces needs yabai's **scripting-addition** loaded

---

## 2. Install ywr

Build a release binary and put it on your `PATH`:

```sh
cd yabai-workspaces
swift build -c release
cp .build/release/ywr ~/.local/bin/ywr    # assuming ~/.local/bin is on PATH
```

Verify:

```sh
ywr doctor
```

`doctor` checks that yabai is installed, responds, and that the needed macOS
settings are in place.

---

## 3. Core workflow: save → restore

```sh
ywr snapshot save home        # capture the current layout as "home"
ywr restore home --dry-run    # preview what restore would do (no changes)
ywr restore home              # move windows back into place
ywr snapshot list             # list saved snapshots
```

---

## 4. Auto-restore

Two ways to restore automatically when the display setup changes — pick one.

**Pick the closest snapshot now:**

```sh
ywr restore --auto
ywr restore --auto --dry-run
```

**Daemon (polling):**

```sh
ywr daemon                 # default 2s interval
ywr daemon --interval 5    # 5s interval; Ctrl-C to stop
```

**yabai signals (event-driven, no daemon):**

```sh
ywr signal install     # register display_added/removed/moved → restore --auto
ywr signal list
ywr signal uninstall
```

---

## 5. Display profiles

```sh
ywr profile capture home   # record the current display configuration
ywr profile list
```

---

## 6. What restore does

- Moves windows to their saved **Display / Space**
- Restores position/size via **relative coordinates** (survives resolution changes)
- Restores **floating / minimized / fullscreen** state
- **Refocuses** the window that was active at capture time
- **Launches** apps that aren't running (`open -a`) and waits briefly
- Prints any windows it **couldn't restore** at the end (no silent failures)

**Create missing Spaces** first:

```sh
ywr restore home --create-spaces
ywr restore home --create-spaces --dry-run
```

---

## 7. Menu-bar app

A SwiftUI menu-bar app mirrors the CLI (save + auto-restore):

```sh
swift run ywr-menubar
```

**Colors and fonts** are set in an external file — no code changes. Drop
`~/.config/yabai-workspaces/theme.json` (built-in dark default if absent):

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

`colors` are `#RRGGBB` or `#RRGGBBAA`; `font.family` is `"System"` or a font name.

---

## 8. Where data lives

Everything is JSON under `$XDG_CONFIG_HOME/yabai-workspaces`
(default `~/.config/yabai-workspaces`):

```
snapshots/<name>.json    profiles/<name>.json    theme.json (optional)
```

---

## 9. Command reference

| Command | Description |
|---|---|
| `ywr doctor` | Check yabai and the environment |
| `ywr snapshot save <name>` | Save the current layout |
| `ywr snapshot list` | List saved snapshots |
| `ywr restore <name> [--dry-run]` | Restore (preview with `--dry-run`) |
| `ywr restore --auto` | Auto-pick the matching snapshot |
| `ywr restore <name> --create-spaces` | Create missing Spaces, then restore |
| `ywr profile capture <name>` / `list` | Record / list display profiles |
| `ywr daemon [--interval <s>]` | Auto-restore by polling |
| `ywr signal install\|uninstall\|list` | Auto-restore via yabai signals |

---

## 10. Troubleshooting

- **`command not found: ywr`** — not on PATH: `swift build -c release && cp .build/release/ywr ~/.local/bin/ywr`.
- **`doctor` shows ✗** — yabai not installed/running: `brew install ... yabai`, `yabai --start-service`.
- **Cross-Space moves don't work** — scripting-addition not loaded, or "Displays have separate Spaces" is OFF.
- **Some windows don't return** — `restore` prints a failure list at the end; use `--dry-run` to inspect matching.
