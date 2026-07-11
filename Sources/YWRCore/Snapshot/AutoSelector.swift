import Foundation

// Implemented via ollama gemma4:31b, reviewed and integrated unchanged.
// Picks the snapshot whose saved display configuration best matches the current
// one, backing `ywr restore --auto`.

public struct ScoredSnapshot: Sendable, Equatable {
    public let snapshot: Snapshot
    public let score: Int
}

public enum AutoSelection: Sendable {
    case confident(ScoredSnapshot)
    case ambiguous([ScoredSnapshot])
    case none
}

public struct AutoSelector: Sendable {
    private let scorer: ConfigurationScorer
    private let threshold: Int
    private let ambiguityMargin: Int

    public init(
        scorer: ConfigurationScorer = ConfigurationScorer(),
        threshold: Int = 70,
        ambiguityMargin: Int = 15
    ) {
        self.scorer = scorer
        self.threshold = threshold
        self.ambiguityMargin = ambiguityMargin
    }

    public func select(from snapshots: [Snapshot], currentDisplays: [Display]) -> AutoSelection {
        guard !snapshots.isEmpty else {
            return .none
        }

        let scored = snapshots.map { snapshot in
            ScoredSnapshot(
                snapshot: snapshot,
                score: scorer.score(savedDisplays: snapshot.displayProfile.displays, currentDisplays: currentDisplays)
            )
        }.sorted { $0.score > $1.score }

        guard let top = scored.first else {
            return .none
        }

        if top.score < threshold {
            return .ambiguous(scored)
        }

        if scored.count == 1 {
            return .confident(top)
        }

        let second = scored[1]
        if (top.score - second.score) >= ambiguityMargin {
            return .confident(top)
        } else {
            let candidates = scored.filter { $0.score >= threshold }
            return .ambiguous(candidates)
        }
    }
}
