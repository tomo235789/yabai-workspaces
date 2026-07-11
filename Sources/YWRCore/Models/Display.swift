import Foundation

/// A display as reported by `yabai -m query --displays`.
public struct Display: Codable, Equatable, Sendable {
    public var id: Int
    public var uuid: String
    public var index: Int
    public var frame: Frame
    public var spaces: [Int]
    public var hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case id, uuid, index, frame, spaces
        case hasFocus = "has-focus"
    }

    public init(id: Int, uuid: String, index: Int, frame: Frame, spaces: [Int], hasFocus: Bool = false) {
        self.id = id
        self.uuid = uuid
        self.index = index
        self.frame = frame
        self.spaces = spaces
        self.hasFocus = hasFocus
    }

    // `has-focus` is absent from some yabai builds; default it rather than fail.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        uuid = try c.decode(String.self, forKey: .uuid)
        index = try c.decode(Int.self, forKey: .index)
        frame = try c.decode(Frame.self, forKey: .frame)
        spaces = try c.decodeIfPresent([Int].self, forKey: .spaces) ?? []
        hasFocus = try c.decodeIfPresent(Bool.self, forKey: .hasFocus) ?? false
    }
}
