import Foundation

// Implemented via ollama gemma4:31b, reviewed and integrated unchanged.
// Decides which missing labeled Spaces to (re)create during restore.

public struct SpaceProvisionRequest: Equatable, Sendable {
    public let displayIndex: Int
    public let label: String

    public init(displayIndex: Int, label: String) {
        self.displayIndex = displayIndex
        self.label = label
    }
}

public struct SpaceProvisioner: Sendable {
    public init() {}

    public func requests(savedSpaces: [SpaceSnapshot], currentSpaces: [Space], displayMap: [Int: Int]) -> [SpaceProvisionRequest] {
        var seenLabels = Set<String>()
        let existingLabels = Set(currentSpaces.map { $0.label })

        return savedSpaces.compactMap { saved in
            let label = saved.label

            guard !label.isEmpty else { return nil }
            guard !existingLabels.contains(label) else { return nil }
            guard !seenLabels.contains(label) else { return nil }

            seenLabels.insert(label)

            let displayIndex = displayMap[saved.display] ?? saved.display
            return SpaceProvisionRequest(displayIndex: displayIndex, label: label)
        }
    }
}
