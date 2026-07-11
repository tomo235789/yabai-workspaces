import Foundation

/// A window as reported by `yabai -m query --windows`. This is the live yabai
/// view; the persisted form is `WindowSnapshot`.
public struct Window: Codable, Equatable, Sendable {
    public var id: Int
    public var pid: Int
    public var app: String
    public var title: String
    public var frame: Frame
    public var role: String
    public var subrole: String
    public var display: Int
    public var space: Int
    public var isVisible: Bool
    public var isFloating: Bool
    public var isSticky: Bool
    public var isMinimized: Bool
    public var isNativeFullscreen: Bool
    public var hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, frame, role, subrole, display, space
        case isVisible = "is-visible"
        case isFloating = "is-floating"
        case isSticky = "is-sticky"
        case isMinimized = "is-minimized"
        case isNativeFullscreen = "is-native-fullscreen"
        case hasFocus = "has-focus"
    }

    public init(
        id: Int,
        pid: Int,
        app: String,
        title: String = "",
        frame: Frame,
        role: String = "AXWindow",
        subrole: String = "AXStandardWindow",
        display: Int,
        space: Int,
        isVisible: Bool = true,
        isFloating: Bool = false,
        isSticky: Bool = false,
        isMinimized: Bool = false,
        isNativeFullscreen: Bool = false,
        hasFocus: Bool = false
    ) {
        self.id = id
        self.pid = pid
        self.app = app
        self.title = title
        self.frame = frame
        self.role = role
        self.subrole = subrole
        self.display = display
        self.space = space
        self.isVisible = isVisible
        self.isFloating = isFloating
        self.isSticky = isSticky
        self.isMinimized = isMinimized
        self.isNativeFullscreen = isNativeFullscreen
        self.hasFocus = hasFocus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        pid = try c.decode(Int.self, forKey: .pid)
        app = try c.decode(String.self, forKey: .app)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        frame = try c.decode(Frame.self, forKey: .frame)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        subrole = try c.decodeIfPresent(String.self, forKey: .subrole) ?? ""
        display = try c.decode(Int.self, forKey: .display)
        space = try c.decode(Int.self, forKey: .space)
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isFloating = try c.decodeIfPresent(Bool.self, forKey: .isFloating) ?? false
        isSticky = try c.decodeIfPresent(Bool.self, forKey: .isSticky) ?? false
        isMinimized = try c.decodeIfPresent(Bool.self, forKey: .isMinimized) ?? false
        isNativeFullscreen = try c.decodeIfPresent(Bool.self, forKey: .isNativeFullscreen) ?? false
        hasFocus = try c.decodeIfPresent(Bool.self, forKey: .hasFocus) ?? false
    }
}
