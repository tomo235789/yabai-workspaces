import Foundation

/// Tunable weights for display scoring. Exposed as data so the policy can be
/// adjusted or A/B'd without editing the matcher (Open/Closed).
public struct MatchWeights: Sendable {
    public var uuid: Int
    public var resolution: Int
    public var frameSize: Int
    public var spacesCount: Int
    public var arrangement: Int
    public var threshold: Int

    public init(
        uuid: Int = 50,
        resolution: Int = 15,
        frameSize: Int = 10,
        spacesCount: Int = 5,
        arrangement: Int = 10,
        threshold: Int = 70
    ) {
        self.uuid = uuid
        self.resolution = resolution
        self.frameSize = frameSize
        self.spacesCount = spacesCount
        self.arrangement = arrangement
        self.threshold = threshold
    }

    public static let `default` = MatchWeights()
}

/// One saved display paired with the current display it best corresponds to.
public struct DisplayCorrespondence: Sendable, Equatable {
    public let savedIndex: Int
    public let currentDisplayIndex: Int
    public let score: Int
    public var isConfident: Bool

    public init(savedIndex: Int, currentDisplayIndex: Int, score: Int, isConfident: Bool) {
        self.savedIndex = savedIndex
        self.currentDisplayIndex = currentDisplayIndex
        self.score = score
        self.isConfident = isConfident
    }
}

public protocol DisplayMatching: Sendable {
    /// Scores how strongly `saved` corresponds to `current`.
    func score(saved: Display, current: Display, allSaved: [Display], allCurrent: [Display]) -> Int

    /// Greedily maps each saved display to the best unused current display.
    func match(saved: [Display], current: [Display]) -> [DisplayCorrespondence]
}

public struct DisplayMatcher: DisplayMatching {
    private let weights: MatchWeights

    public init(weights: MatchWeights = .default) {
        self.weights = weights
    }

    public func score(saved: Display, current: Display, allSaved: [Display], allCurrent: [Display]) -> Int {
        var total = 0

        if !saved.uuid.isEmpty, saved.uuid == current.uuid {
            total += weights.uuid
        }
        if sameResolution(saved.frame, current.frame) {
            total += weights.resolution
        } else if closeSize(saved.frame, current.frame, tolerance: 0.1) {
            // Partial credit when the panel is close but not identical.
            total += weights.frameSize
        }
        if abs(saved.spaces.count - current.spaces.count) <= 1 {
            total += weights.spacesCount
        }
        if similarArrangement(saved, current, allSaved: allSaved, allCurrent: allCurrent) {
            total += weights.arrangement
        }
        return total
    }

    public func match(saved: [Display], current: [Display]) -> [DisplayCorrespondence] {
        var usedCurrent = Set<Int>()
        var result: [DisplayCorrespondence] = []

        // Match highest-confidence pairs first so a strong uuid hit isn't stolen
        // by an earlier weakly-matched saved display.
        let candidates = saved.enumerated().flatMap { savedIdx, s in
            current.enumerated().map { curIdx, c in
                (savedIdx: savedIdx, curIdx: curIdx,
                 score: score(saved: s, current: c, allSaved: saved, allCurrent: current))
            }
        }.sorted { $0.score > $1.score }

        var assignedSaved = Set<Int>()
        for cand in candidates {
            guard !assignedSaved.contains(cand.savedIdx), !usedCurrent.contains(cand.curIdx) else { continue }
            assignedSaved.insert(cand.savedIdx)
            usedCurrent.insert(cand.curIdx)
            result.append(DisplayCorrespondence(
                savedIndex: cand.savedIdx,
                currentDisplayIndex: current[cand.curIdx].index,
                score: cand.score,
                isConfident: cand.score >= weights.threshold
            ))
        }
        return result.sorted { $0.savedIndex < $1.savedIndex }
    }

    // MARK: - Helpers

    private func sameResolution(_ a: Frame, _ b: Frame) -> Bool {
        Int(a.w.rounded()) == Int(b.w.rounded()) && Int(a.h.rounded()) == Int(b.h.rounded())
    }

    private func closeSize(_ a: Frame, _ b: Frame, tolerance: Double) -> Bool {
        guard a.w > 0, a.h > 0 else { return false }
        return abs(a.w - b.w) / a.w <= tolerance && abs(a.h - b.h) / a.h <= tolerance
    }

    /// True when both displays sit in the same order along the x axis relative
    /// to their peers (leftmost stays leftmost, etc.).
    private func similarArrangement(_ saved: Display, _ current: Display, allSaved: [Display], allCurrent: [Display]) -> Bool {
        func rank(_ d: Display, in all: [Display]) -> Int {
            all.filter { $0.frame.x < d.frame.x }.count
        }
        return rank(saved, in: allSaved) == rank(current, in: allCurrent)
    }
}

/// Scores a whole saved snapshot against the current configuration — used by
/// `restore --auto` to pick the closest snapshot.
public struct ConfigurationScorer: Sendable {
    private let matcher: DisplayMatching

    public init(matcher: DisplayMatching = DisplayMatcher()) {
        self.matcher = matcher
    }

    public func score(savedDisplays: [Display], currentDisplays: [Display]) -> Int {
        matcher.match(saved: savedDisplays, current: currentDisplays)
            .map(\.score)
            .reduce(0, +)
    }
}
