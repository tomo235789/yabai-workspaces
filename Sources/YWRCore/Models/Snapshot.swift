import Foundation

/// Window flags persisted in a snapshot.
public struct WindowFlags: Codable, Equatable, Sendable {
    public var floating: Bool
    public var sticky: Bool
    public var minimized: Bool
    public var fullscreen: Bool

    public init(floating: Bool, sticky: Bool, minimized: Bool, fullscreen: Bool) {
        self.floating = floating
        self.sticky = sticky
        self.minimized = minimized
        self.fullscreen = fullscreen
    }
}

/// The persisted form of a window: enough identity to re-match it later plus
/// both absolute and display-relative geometry.
public struct WindowSnapshot: Codable, Equatable, Sendable {
    public var app: String
    public var title: String
    public var role: String
    public var pid: Int
    public var space: Int
    public var display: Int
    public var frame: Frame
    public var relativeFrame: RelativeFrame
    public var flags: WindowFlags
    /// Whether this window had keyboard focus at capture time. Restore refocuses
    /// it last so the layout comes back with the same active window.
    public var focused: Bool

    public init(
        app: String,
        title: String,
        role: String,
        pid: Int,
        space: Int,
        display: Int,
        frame: Frame,
        relativeFrame: RelativeFrame,
        flags: WindowFlags,
        focused: Bool = false
    ) {
        self.app = app
        self.title = title
        self.role = role
        self.pid = pid
        self.space = space
        self.display = display
        self.frame = frame
        self.relativeFrame = relativeFrame
        self.flags = flags
        self.focused = focused
    }

    // `focused` is new; decode it as false when reading older snapshots.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decode(String.self, forKey: .app)
        title = try c.decode(String.self, forKey: .title)
        role = try c.decode(String.self, forKey: .role)
        pid = try c.decode(Int.self, forKey: .pid)
        space = try c.decode(Int.self, forKey: .space)
        display = try c.decode(Int.self, forKey: .display)
        frame = try c.decode(Frame.self, forKey: .frame)
        relativeFrame = try c.decode(RelativeFrame.self, forKey: .relativeFrame)
        flags = try c.decode(WindowFlags.self, forKey: .flags)
        focused = try c.decodeIfPresent(Bool.self, forKey: .focused) ?? false
    }
}

/// A Space persisted in a snapshot — only the fields restore needs.
public struct SpaceSnapshot: Codable, Equatable, Sendable {
    public var index: Int
    public var label: String
    public var display: Int

    public init(index: Int, label: String, display: Int) {
        self.index = index
        self.label = label
        self.display = display
    }
}

/// A display-configuration fingerprint plus the raw displays it was built from.
public struct DisplayProfile: Codable, Equatable, Sendable {
    public var fingerprint: String
    public var displays: [Display]

    public init(fingerprint: String, displays: [Display]) {
        self.fingerprint = fingerprint
        self.displays = displays
    }
}

/// The top-level artifact written by `snapshot save` and read by `restore`.
public struct Snapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var name: String
    public var capturedAt: Date
    public var displayProfile: DisplayProfile
    public var spaces: [SpaceSnapshot]
    public var windows: [WindowSnapshot]

    public init(
        version: Int = Snapshot.currentVersion,
        name: String,
        capturedAt: Date,
        displayProfile: DisplayProfile,
        spaces: [SpaceSnapshot],
        windows: [WindowSnapshot]
    ) {
        self.version = version
        self.name = name
        self.capturedAt = capturedAt
        self.displayProfile = displayProfile
        self.spaces = spaces
        self.windows = windows
    }
}
