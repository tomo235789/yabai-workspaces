import CoreGraphics
import Foundation

// Experimental "walk the desktops" restore for the native (yabai-independent)
// backend. The public macOS APIs can't MOVE a window to another Space, but a
// window can be repositioned by Accessibility once its Space is active. So we
// switch through each desktop and, on every one, place whichever saved windows
// live there — reproducing a multi-desktop layout with one click, without any
// private window-moving API.
//
// Every side effect (switching Spaces, probing the active Space, waiting for the
// switch animation) sits behind a protocol so the walk logic is unit-tested with
// in-memory fakes.

/// Switches the active desktop (Space) forward/backward. The real implementation
/// synthesizes the system "move one space left/right" keyboard shortcuts.
public protocol SpaceSwitching: Sendable {
    func switchToNextSpace()
    func switchToPreviousSpace()
}

/// Returns a stable identifier for the currently-active Space, used to detect
/// when a switch actually changed desktops (vs. hitting an edge). Must uniquely
/// identify EMPTY desktops too — on-screen window sets can't, so the real
/// implementation reads the Space id from the window server.
public protocol ActiveSpaceIdentifying: Sendable {
    func currentSpaceID() -> UInt64
}

// Read-only window-server calls to identify the active Space. These are private
// but require no code injection / SIP changes (unlike the APIs that MOVE windows
// between Spaces) — we only READ which Space is active, to know when a switch
// crossed a desktop boundary.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ connection: Int32) -> UInt64

/// Synthesizes Ctrl+Arrow to switch Spaces. Needs the "Mission Control ▸ Move
/// left/right a space" shortcuts enabled (default on macOS) and Accessibility
/// permission to post events.
public struct KeyboardSpaceSwitcher: SpaceSwitching {
    private let rightArrow: CGKeyCode = 0x7C   // kVK_RightArrow
    private let leftArrow: CGKeyCode = 0x7B    // kVK_LeftArrow

    public init() {}

    public func switchToNextSpace() { postControl(rightArrow) }
    public func switchToPreviousSpace() { postControl(leftArrow) }

    private func postControl(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskControl
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskControl
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Identifies the active Space via the window server (distinguishes empty
/// desktops, which on-screen window ids cannot).
public struct CGActiveSpaceProbe: ActiveSpaceIdentifying {
    public init() {}

    public func currentSpaceID() -> UInt64 {
        CGSGetActiveSpace(CGSMainConnectionID())
    }
}

/// Restores a native snapshot by cycling through every desktop and placing the
/// windows that belong to each. Matching is done once up-front (pure); placement
/// is retried on each Space until it succeeds or the walk ends.
///
/// Scope: this targets the "spanning" configuration ("Displays have separate
/// Spaces" OFF), where Ctrl+Arrow moves a single shared Space set across all
/// displays — the setup where yabai can't run and the native backend is used. If
/// "separate Spaces" is ON (each display has its own Space row), Ctrl+Arrow only
/// affects the focused display, so windows on other displays' Spaces won't be
/// reached; that configuration should use the yabai backend instead.
public struct WalkingNativeRestorer {
    private let enumerator: NativeWindowEnumerating
    private let controller: NativeWindowControlling
    private let matcher: WindowMatching
    private let switcher: SpaceSwitching
    private let probe: ActiveSpaceIdentifying
    /// Pause for the Space-switch animation before touching windows. Injected so
    /// tests run instantly.
    private let waitForSwitch: @Sendable () -> Void
    /// Safety cap on how many desktops to visit (avoids infinite cycling if the
    /// loop signature never repeats).
    private let maxSpaces: Int
    /// How many times to poll for the Space id to change after a switch before
    /// concluding it was a no-op (an edge). Combined with `waitForSwitch` this is
    /// the total tolerance for a slow Space-switch animation.
    private let pollAttempts: Int

    public init(
        enumerator: NativeWindowEnumerating,
        controller: NativeWindowControlling,
        matcher: WindowMatching = WindowMatcher(),
        switcher: SpaceSwitching = KeyboardSpaceSwitcher(),
        probe: ActiveSpaceIdentifying = CGActiveSpaceProbe(),
        waitForSwitch: @escaping @Sendable () -> Void = { Thread.sleep(forTimeInterval: 0.2) },
        maxSpaces: Int = 32,
        pollAttempts: Int = 6
    ) {
        self.enumerator = enumerator
        self.controller = controller
        self.matcher = matcher
        self.switcher = switcher
        self.probe = probe
        self.waitForSwitch = waitForSwitch
        self.maxSpaces = maxSpaces
        self.pollAttempts = pollAttempts
    }

    /// One saved window paired with the live window it matched (still to place).
    private struct Pending {
        let index: Int          // position in saved order (0 == frontmost)
        let label: String
        let frame: Frame
        let pid: Int
        let windowID: UInt32
    }

    public func restore(_ snapshot: Snapshot) -> RestoreReport {
        var available = enumerator.enumerate()
        var pending: [Pending] = []
        var outcomes: [RestoreOutcome] = []

        // Match once against all live windows (across every Space). A saved
        // window with no live counterpart anywhere is unmatched regardless of
        // which desktop is active, so decide that up-front.
        for (index, saved) in snapshot.windows.enumerated() {
            let label = "\(saved.app) — \(saved.title.isEmpty ? "(untitled)" : saved.title)"
            if let match = matcher.bestMatch(for: saved, among: available) {
                available.removeAll { $0.id == match.id }
                pending.append(Pending(index: index, label: label, frame: saved.frame,
                                       pid: match.pid, windowID: CGWindowID(match.id)))
            } else {
                outcomes.append(RestoreOutcome(label: label, status: .unmatched))
            }
        }

        // Nothing matched a live window — don't flip through desktops for no
        // reason; the report already holds the unmatched outcomes.
        guard !pending.isEmpty else { return RestoreReport(outcomes: outcomes) }

        walk(pending: &pending, outcomes: &outcomes)

        // Whatever is still pending after visiting the desktops couldn't be
        // driven (e.g. missing Accessibility permission) — report as failed.
        for item in pending {
            outcomes.append(RestoreOutcome(label: item.label, status: .failed(reason: "could not move window (check Accessibility permission and Mission Control space-switching shortcuts)")))
        }

        return RestoreReport(outcomes: outcomes)
    }

    /// Visits every desktop, placing every pending window whose Space is now
    /// active, and leaves the user on the desktop they started on.
    ///
    /// macOS's "move one space" shortcut does NOT wrap at the ends, so we can't
    /// rely on cycling back home. Instead: walk LEFT to the left edge (detected
    /// when a switch stops changing the active Space), then sweep RIGHT across
    /// every desktop, then return to the starting index. Boundaries are found by
    /// comparing the active-Space id before and after each switch.
    private func walk(pending: inout [Pending], outcomes: inout [RestoreOutcome]) {
        // Placed windows tagged with the desktop index they landed on, so we can
        // raise the frontmost one WITHOUT leaving home (see Phase D).
        var placed: [(item: Pending, spaceIndex: Int)] = []

        // Phase A — go to the leftmost desktop, recording how many desktops home
        // is from the left edge so we can come back to it.
        var homeIndex = 0
        var guardCount = 0
        while guardCount < maxSpaces {
            guardCount += 1
            if !switchAndConfirm({ switcher.switchToPreviousSpace() }) { break }   // left edge
            homeIndex += 1
        }

        // Phase B — sweep right across every desktop, placing as we go. Always
        // place on the current desktop BEFORE deciding whether to switch, so the
        // last desktop reached is processed even when the safety cap is hit.
        var index = 0
        while true {
            placeOnActiveSpace(spaceIndex: index, pending: &pending, placed: &placed, outcomes: &outcomes)
            if pending.isEmpty || index >= maxSpaces { break }
            if !switchAndConfirm({ switcher.switchToNextSpace() }) { break }        // right edge
            index += 1
        }

        // Phase C — return to the starting desktop by index. Only advance the
        // position on a CONFIRMED switch; if one is dropped, stop rather than
        // over-shoot and believe we're home when we aren't.
        while index > homeIndex {
            if switchAndConfirm({ switcher.switchToPreviousSpace() }) { index -= 1 } else { break }
        }
        while index < homeIndex {
            if switchAndConfirm({ switcher.switchToNextSpace() }) { index += 1 } else { break }
        }

        // Phase D — raise the frontmost placed window, but ONLY if we actually
        // returned home AND that window lives on the home desktop. Raising a
        // window on another desktop would make macOS switch there, breaking the
        // "returns you home" contract.
        guard index == homeIndex else { return }
        let atHome = placed.filter { $0.spaceIndex == homeIndex }
        if let front = atHome.min(by: { $0.item.index < $1.item.index }) {
            try? controller.raise(pid: front.item.pid, windowID: front.item.windowID)
        }
    }

    /// Issues a Space switch, then polls the active-Space id until it changes or
    /// the poll budget runs out. Returns whether the desktop actually changed —
    /// `false` means the switch was a no-op (an edge). Polling (rather than a
    /// single fixed sleep) keeps a slow Space animation from being mistaken for
    /// an edge, which would stop the walk early.
    private func switchAndConfirm(_ performSwitch: () -> Void) -> Bool {
        let before = probe.currentSpaceID()
        performSwitch()
        for _ in 0..<max(1, pollAttempts) {
            waitForSwitch()
            if probe.currentSpaceID() != before { return true }
        }
        return false
    }

    /// Places every pending window that can be moved on the currently-active
    /// desktop; ones on other desktops throw and remain pending.
    private func placeOnActiveSpace(spaceIndex: Int, pending: inout [Pending], placed: inout [(item: Pending, spaceIndex: Int)], outcomes: inout [RestoreOutcome]) {
        pending.removeAll { item in
            do {
                try controller.setFrame(pid: item.pid, windowID: item.windowID, to: item.frame)
                outcomes.append(RestoreOutcome(label: item.label, status: .movedPositionsOnly))
                placed.append((item: item, spaceIndex: spaceIndex))
                return true
            } catch {
                return false
            }
        }
    }
}
