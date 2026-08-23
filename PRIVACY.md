# Privacy

**ywr (yabai workspaces) collects nothing and sends nothing.** It has no
servers, no analytics, no telemetry, no accounts, and makes no network requests.
Everything happens locally on your Mac.

## What it accesses, and why

To save and restore window layouts, ywr reads and moves windows on your Mac:

- **Window geometry and metadata** — each window's app, title, position, size,
  and which Display/Space it's on. Read via the macOS Accessibility API,
  CoreGraphics window list, and (when installed) `yabai -m`.
- **Accessibility permission** (required) — lets ywr move and resize windows.
  Granted by you in System Settings ▸ Privacy & Security ▸ Accessibility.
- **Screen Recording permission** (optional) — only used so window **titles** can
  be read, which improves matching windows across app restarts. Denying it just
  makes matching less precise; ywr still works.

ywr does **not** read window *contents*, take screenshots, or capture the screen
— the Screen Recording permission is required by macOS merely to expose window
titles, not to record anything.

## Where your data is stored

Snapshots and display profiles are plain JSON files under your own home folder:

```
$XDG_CONFIG_HOME/yabai-workspaces      (default: ~/.config/yabai-workspaces)
  snapshots/<name>.json
  profiles/<name>.json
  theme.json            (optional menu-bar theme)
```

These files never leave your machine. Delete them at any time (or use
`ywr snapshot delete <name>`).

## Third parties

ywr optionally shells out to [yabai](https://github.com/koekeishiya/yabai) if it
is installed. yabai is a separate project with its own behavior; ywr does not
bundle it and does not send it any of your data beyond the local `yabai -m`
commands needed to query and arrange windows.

## Contact

Questions about privacy: open an issue at
<https://github.com/tomo235789/yabai-workspaces>.
