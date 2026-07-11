import Foundation

/// Turns a saved snapshot + the current live configuration into a concrete,
/// inspectable `RestorePlan`. Pure (no side effects), so it is fully unit
/// testable and drives both `--dry-run` and real execution.
public struct RestorePlanner: Sendable {
    private let displayMatcher: DisplayMatching
    private let windowMatcher: WindowMatching

    public init(
        displayMatcher: DisplayMatching = DisplayMatcher(),
        windowMatcher: WindowMatching = WindowMatcher()
    ) {
        self.displayMatcher = displayMatcher
        self.windowMatcher = windowMatcher
    }

    public func plan(
        snapshot: Snapshot,
        currentDisplays: [Display],
        currentSpaces: [Space],
        currentWindows: [Window]
    ) -> RestorePlan {
        var plan = RestorePlan()

        // 1. Map saved display index -> current display index.
        let correspondences = displayMatcher.match(
            saved: snapshot.displayProfile.displays,
            current: currentDisplays
        )
        var savedDisplayIndexToCurrent: [Int: Int] = [:]
        for c in correspondences {
            let savedDisplay = snapshot.displayProfile.displays[c.savedIndex]
            savedDisplayIndexToCurrent[savedDisplay.index] = c.currentDisplayIndex
        }
        let currentDisplayByIndex = Dictionary(uniqueKeysWithValues: currentDisplays.map { ($0.index, $0) })

        // 2. Space mapping (label first, index fallback).
        let savedSpaceByIndex = Dictionary(uniqueKeysWithValues: snapshot.spaces.map { ($0.index, $0) })
        let currentSpaceIndices = Set(currentSpaces.map(\.index))
        func targetSpaceIndex(forSaved savedSpaceIndex: Int) -> Int {
            if let saved = savedSpaceByIndex[savedSpaceIndex], !saved.label.isEmpty,
               let match = currentSpaces.first(where: { $0.label == saved.label }) {
                return match.index
            }
            return currentSpaceIndices.contains(savedSpaceIndex) ? savedSpaceIndex : (currentSpaces.first?.index ?? savedSpaceIndex)
        }

        // 3. Space labels worth re-applying.
        for saved in snapshot.spaces where !saved.label.isEmpty {
            let idx = targetSpaceIndex(forSaved: saved.index)
            if !currentSpaces.contains(where: { $0.label == saved.label }) {
                plan.spaceLabels.append((spaceIndex: idx, label: saved.label))
            }
        }

        // 4. Window steps. Consume matched live windows so no two saved windows
        // claim the same one.
        var availableWindows = currentWindows
        let runningApps = Set(currentWindows.map(\.app))
        var appsToLaunch = Set<String>()

        for saved in snapshot.windows {
            let targetDisplayIndex = savedDisplayIndexToCurrent[saved.display]
                ?? currentDisplays.first?.index ?? saved.display
            let displayFrame = currentDisplayByIndex[targetDisplayIndex]?.frame
                ?? Frame(x: 0, y: 0, w: saved.frame.w, h: saved.frame.h)
            let targetFrame = saved.relativeFrame.resolved(on: displayFrame)
            let spaceIndex = targetSpaceIndex(forSaved: saved.space)

            if let match = windowMatcher.bestMatch(for: saved, among: availableWindows) {
                availableWindows.removeAll { $0.id == match.id }
                plan.steps.append(WindowRestoreStep(
                    saved: saved,
                    matchedWindowId: match.id,
                    targetDisplayIndex: targetDisplayIndex,
                    targetSpaceIndex: spaceIndex,
                    targetFrame: targetFrame,
                    shouldFloat: saved.flags.floating
                ))
            } else if runningApps.contains(saved.app) {
                // App is up but we couldn't identify this specific window.
                plan.unmatched.append(saved)
            } else {
                // Not running: schedule a launch, defer the geometry step.
                appsToLaunch.insert(saved.app)
                plan.steps.append(WindowRestoreStep(
                    saved: saved,
                    matchedWindowId: nil,
                    targetDisplayIndex: targetDisplayIndex,
                    targetSpaceIndex: spaceIndex,
                    targetFrame: targetFrame,
                    shouldFloat: saved.flags.floating
                ))
            }
        }
        plan.appsToLaunch = appsToLaunch.sorted()
        return plan
    }
}
