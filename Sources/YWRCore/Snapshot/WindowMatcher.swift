import Foundation

public protocol WindowMatching: Sendable {
    /// Finds the current window that best corresponds to `saved`, consuming it
    /// so two saved windows can't claim the same live window.
    func bestMatch(for saved: WindowSnapshot, among candidates: [Window]) -> Window?
}

/// Scores candidate windows by app (required), then title, role and size.
/// Window ids are intentionally NOT used — they change across restarts, which
/// is exactly why identity has to be reconstructed heuristically.
public struct WindowMatcher: WindowMatching {
    public init() {}

    public func bestMatch(for saved: WindowSnapshot, among candidates: [Window]) -> Window? {
        let sameApp = candidates.filter { $0.app == saved.app }
        guard !sameApp.isEmpty else { return nil }

        return sameApp
            .map { (window: $0, score: score(saved: saved, candidate: $0)) }
            .max { $0.score < $1.score }
            .map(\.window)
    }

    func score(saved: WindowSnapshot, candidate: Window) -> Int {
        var total = 0
        if saved.title == candidate.title, !saved.title.isEmpty {
            total += 50
        } else if !saved.title.isEmpty, candidate.title.contains(saved.title) || saved.title.contains(candidate.title) {
            total += 20
        }
        if saved.role == candidate.role, !saved.role.isEmpty {
            total += 15
        }
        if closeSize(saved.frame, candidate.frame, tolerance: 0.15) {
            total += 15
        }
        return total
    }

    private func closeSize(_ a: Frame, _ b: Frame, tolerance: Double) -> Bool {
        guard a.w > 0, a.h > 0 else { return false }
        return abs(a.w - b.w) / a.w <= tolerance && abs(a.h - b.h) / a.h <= tolerance
    }
}
