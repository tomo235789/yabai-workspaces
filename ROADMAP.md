# ywr Roadmap

## Implemented

- Snapshot v2 records `spaceMode`; v1 snapshots remain readable as `unknown`.
- Capture detects the macOS `spans-displays` preference through an injected detector.
- Unified-desktop restore discovers windows by visiting non-fullscreen Spaces and always attempts to return to the original Space.
- Physical displays remain placement anchors for display-relative window geometry.

## Next

- Replace the fixed Space activation delay with state polling and a configurable timeout.
- Validate live and captured `spaceMode` before restore and define mismatch policies (`abort`, `warn`, `convert`).
- Group planning, execution, dry-run output, and failure reporting by stable virtual-desktop references (label, ordinal, live index).
- Add missing virtual-desktop creation with per-desktop failure isolation.
- Reduce visible desktop switching during discovery where future macOS/yabai APIs allow it.

## Later

- Persist a restore journal with execution IDs, before/after state, resumption, and stale-run cleanup.
- Add daemon de-duplication and cancellation when topology events arrive during restore.
- Add real-machine end-to-end coverage for both values of “Displays have separate Spaces”.
- Add configurable missing-display policies and on-screen containment.
