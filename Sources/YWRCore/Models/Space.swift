import Foundation

/// A Space (Mission Control desktop) as reported by `yabai -m query --spaces`.
public struct Space: Codable, Equatable, Sendable {
    public var id: Int
    public var index: Int
    public var label: String
    public var display: Int
    public var windows: [Int]
    public var hasFocus: Bool
    public var isNativeFullscreen: Bool

    enum CodingKeys: String, CodingKey {
        case id, index, label, display, windows
        case hasFocus = "has-focus"
        case isNativeFullscreen = "is-native-fullscreen"
    }

    public init(
        id: Int,
        index: Int,
        label: String = "",
        display: Int,
        windows: [Int] = [],
        hasFocus: Bool = false,
        isNativeFullscreen: Bool = false
    ) {
        self.id = id
        self.index = index
        self.label = label
        self.display = display
        self.windows = windows
        self.hasFocus = hasFocus
        self.isNativeFullscreen = isNativeFullscreen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        index = try c.decode(Int.self, forKey: .index)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        display = try c.decode(Int.self, forKey: .display)
        windows = try c.decodeIfPresent([Int].self, forKey: .windows) ?? []
        hasFocus = try c.decodeIfPresent(Bool.self, forKey: .hasFocus) ?? false
        isNativeFullscreen = try c.decodeIfPresent(Bool.self, forKey: .isNativeFullscreen) ?? false
    }

    /// True when this Space carries a user-assigned label (vs. index-only).
    public var hasLabel: Bool { !label.isEmpty }
}
