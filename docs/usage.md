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

Permissions & settings:

- **yabai Accessibility permission** — required to move/resize windows at all
  (**including positions-only restore**).
- Full restore **across Spaces / displays** additionally needs:
  - System Settings ▸ Desktop & Dock ▸ "Displays have separate Spaces" = ON
  - the yabai **scripting-addition** loaded
- Without those extras, ywr automatically falls back to positions-only
  (`ywr doctor` shows the status). Note: a single display can still have
  multiple Spaces (Space moves work); a single display only removes
  cross-display moves.

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

## 4. Display profiles

```sh
ywr profile capture home   # record the current display configuration
ywr profile list
```

---

## 5. What restore does

- Moves windows to their saved **Display / Space**
- Restores position/size via **relative coordinates** (survives resolution changes)
- Restores **floating / minimized / fullscreen** state
- **Refocuses** the window that was active at capture time
- **Launches** apps that aren't running (`open -a`) and waits briefly
- Prints any windows it **couldn't restore** at the end (no silent failures)

**Positions-only / auto-fallback.** On setups where cross-Space/display moves
aren't available (for example, when Space movement fails or scripting addition
is unavailable), ywr still restores each window's position/size on the current
Space. A single display still supports moves between Spaces; only
cross-display movement is unavailable:

- **Default is auto-fallback**: a full restore is attempted first, and any window
  whose Display/Space move fails degrades to positions-only (not a failure). The
  summary reports "N positions-only".
- **Explicit**: `--positions-only` skips Display/Space moves from the start.

```sh
ywr restore home                  # auto-fallback (default)
ywr restore home --positions-only # geometry only, no Space/display moves
```

**Create missing Spaces** first (cannot be combined with `--positions-only` —
doing so is an error):

```sh
ywr restore home --create-spaces
ywr restore home --create-spaces --dry-run
```

### Native backend (works without yabai)

yabai refuses to start when "Displays have separate Spaces" is off. For those
setups, ywr can save/restore window **position and size** through a
yabai-independent **native backend** (macOS Accessibility / CoreGraphics).

- **Automatic**: when `ywr doctor` finds yabai isn't answering, `snapshot save`
  and `restore` use the native backend automatically (shown in the
  `active backend` line).
- **Explicit**: pass `--native` to always use it.

```sh
ywr snapshot save home --native   # capture without yabai
ywr restore home --native         # restore geometry (moves across displays too)
```

What it does / limits:

- ✅ Restores window **position and size**, including **moving across displays**.
- ✅ Brings the window that was **frontmost** at capture time back to the front.
- ✅ Regular GUI apps only (system/helper windows are dropped); Electron/Chromium supported.
- ❌ **No Space assignment** — geometry-only, a limit of the public APIs.
- ❌ `--create-spaces` requires yabai and is rejected in native mode.
- ⚠️ Needs **Accessibility** permission. Granting **Screen Recording** too improves
  matching same-title windows across app restarts.

**Restore across all desktops (experimental).** Public APIs can't *move* a window
to another Space, but a window can be repositioned once its desktop is active. So
`--walk-spaces` switches through each desktop and places the windows already on
it, reproducing a multi-desktop layout in one go — then returns you to where you
started:

```sh
ywr restore home --native --walk-spaces
```

- The screen **flips through each desktop** and it takes a few seconds.
- Windows are **not moved between desktops** — each is repositioned on the desktop
  it currently lives on.
- Needs the **"Mission Control ▸ Move left/right a space"** keyboard shortcuts
  enabled (macOS default) plus Accessibility permission.
- Designed for the **spanning** setup ("Displays have separate Spaces" OFF),
  where one Space set spans all displays. With separate Spaces ON, Ctrl+Arrow
  only moves the focused display's Spaces — use the **yabai backend** there.
- In the menu-bar app this is the **▦ button** next to each snapshot. In native
  mode a plain name-click restores only the **current** desktop; with the yabai
  backend a name-click restores each window's saved Space/Display directly.

---

## 6. Menu-bar app

A SwiftUI menu-bar app mirrors the CLI (save + restore):

```sh
swift run ywr-menubar
```

**If the menu-bar icon doesn't appear**, launch it as an `.app` bundle — macOS
reliably shows the menu-bar item for a bundled LSUIElement (accessory) app:

Build `build/YabaiWorkspaces.app` and open it (the ▤ icon appears in the menu bar):

```sh
bash scripts/make-menubar-app.sh && open build/YabaiWorkspaces.app
```

On first launch the app **prompts for Accessibility** (required to move windows)
and **Screen Recording** (optional, improves window-title matching), registering
itself in System Settings ▸ Privacy & Security. Enable **Accessibility** for
"yabai workspaces" there.

**Keep the grant across rebuilds.** By default the bundle is ad-hoc signed, so
every rebuild looks like a new app to macOS and you must re-add it under
Accessibility. Create a stable self-signed certificate **once** and the grant
sticks across rebuilds (the signature's designated requirement is keyed on the
certificate, not the changing binary hash):

```sh
bash scripts/create-signing-cert.sh   # one-time; no sudo, no prompts
bash scripts/make-menubar-app.sh      # now signs with that identity
```

Grant Accessibility once more after the first stable-signed build (the signature
changed from ad-hoc); after that, rebuilds keep the grant.

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

## 7. Where data lives

Everything is JSON under `$XDG_CONFIG_HOME/yabai-workspaces`
(default `~/.config/yabai-workspaces`):

```text
snapshots/<name>.json    profiles/<name>.json    theme.json (optional)
```

---

## 8. Command reference

| Command | Description |
|---|---|
| `ywr doctor` | Check yabai and the environment |
| `ywr snapshot save <name>` | Save the current layout |
| `ywr snapshot list` | List saved snapshots |
| `ywr snapshot delete <name>` | Delete a saved snapshot |
| `ywr restore <name> [--dry-run]` | Restore (preview with `--dry-run`) |
| `ywr restore <name> --create-spaces` | Create missing Spaces, then restore |
| `ywr restore <name> --positions-only` | Geometry only; no Space/display moves |
| `ywr restore <name> --native --walk-spaces` | Restore across all desktops (walks Spaces) |
| `ywr snapshot save <name> --native` / `ywr restore <name> --native` | Save/restore geometry without yabai |
| `ywr profile capture <name>` / `list` | Record / list display profiles |

---

## 9. Troubleshooting

- **`command not found: ywr`** — not on PATH: `swift build -c release && cp .build/release/ywr ~/.local/bin/ywr`.
- **`doctor` shows ✗** — yabai not installed/running: `brew install ... yabai`, `yabai --start-service`.
- **Cross-Space moves don't work** — scripting-addition not loaded, or "Displays have separate Spaces" is OFF. Positions-only restore still works, and ywr auto-falls-back to it (or force it with `--positions-only`).
- **Some windows don't return** — `restore` prints a failure list at the end; use `--dry-run` to inspect matching.
