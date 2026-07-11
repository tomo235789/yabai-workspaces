import Foundation

/// Read-only access to yabai state. Split from `YabaiControlling` so callers
/// that only observe (e.g. capture, doctor) don't depend on mutation methods
/// they never use — Interface Segregation.
public protocol YabaiQuerying: Sendable {
    func queryDisplays() throws -> [Display]
    func querySpaces() throws -> [Space]
    func queryWindows() throws -> [Window]
}

/// Mutating operations used during restore.
public protocol YabaiControlling: Sendable {
    func moveWindow(_ id: Int, toSpace spaceIndex: Int) throws
    func moveWindow(_ id: Int, toDisplay displayIndex: Int) throws
    func setFloating(_ id: Int, _ floating: Bool) throws
    func moveWindow(_ id: Int, toX x: Double, y: Double) throws
    func resizeWindow(_ id: Int, toW w: Double, h: Double) throws
    func focusWindow(_ id: Int) throws
    func labelSpace(index: Int, label: String) throws
    func createSpace(onDisplay displayIndex: Int) throws
    func setMinimized(_ id: Int, _ minimized: Bool) throws
    func setFullscreen(_ id: Int, _ fullscreen: Bool) throws
}

/// Concrete yabai adapter. Depends only on the `CommandRunner` abstraction, so
/// it works identically against the real binary or an in-memory fake.
public struct YabaiClient: YabaiQuerying, YabaiControlling {
    private let runner: CommandRunner
    private let executable: String

    public init(runner: CommandRunner, executable: String = "yabai") {
        self.runner = runner
        self.executable = executable
    }

    // MARK: - Querying

    public func queryDisplays() throws -> [Display] {
        try decode([Display].self, from: ["-m", "query", "--displays"])
    }

    public func querySpaces() throws -> [Space] {
        try decode([Space].self, from: ["-m", "query", "--spaces"])
    }

    public func queryWindows() throws -> [Window] {
        try decode([Window].self, from: ["-m", "query", "--windows"])
    }

    private func decode<T: Decodable>(_ type: T.Type, from args: [String]) throws -> T {
        let json = try runner.output(executable, args)
        guard let data = json.data(using: .utf8) else {
            throw YabaiError.invalidOutput(command: args.joined(separator: " "))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw YabaiError.decodeFailed(command: args.joined(separator: " "), underlying: error)
        }
    }

    // MARK: - Controlling

    public func moveWindow(_ id: Int, toSpace spaceIndex: Int) throws {
        try control(["-m", "window", "\(id)", "--space", "\(spaceIndex)"])
    }

    public func moveWindow(_ id: Int, toDisplay displayIndex: Int) throws {
        try control(["-m", "window", "\(id)", "--display", "\(displayIndex)"])
    }

    public func setFloating(_ id: Int, _ floating: Bool) throws {
        // yabai only exposes a toggle; callers should read current state first,
        // but expose an explicit setter via query to keep intent clear.
        let windows = try queryWindows()
        guard let current = windows.first(where: { $0.id == id }) else { return }
        if current.isFloating != floating {
            try control(["-m", "window", "\(id)", "--toggle", "float"])
        }
    }

    public func moveWindow(_ id: Int, toX x: Double, y: Double) throws {
        try control(["-m", "window", "\(id)", "--move", "abs:\(Int(x.rounded())):\(Int(y.rounded()))"])
    }

    public func resizeWindow(_ id: Int, toW w: Double, h: Double) throws {
        try control(["-m", "window", "\(id)", "--resize", "abs:\(Int(w.rounded())):\(Int(h.rounded()))"])
    }

    public func focusWindow(_ id: Int) throws {
        try control(["-m", "window", "\(id)", "--focus"])
    }

    public func labelSpace(index: Int, label: String) throws {
        try control(["-m", "space", "\(index)", "--label", label])
    }

    public func createSpace(onDisplay displayIndex: Int) throws {
        // yabai creates the new space on the active display, so focus it first.
        try control(["-m", "display", "--focus", "\(displayIndex)"])
        try control(["-m", "space", "--create"])
    }

    public func setMinimized(_ id: Int, _ minimized: Bool) throws {
        let windows = try queryWindows()
        guard let current = windows.first(where: { $0.id == id }) else { return }
        if current.isMinimized != minimized {
            try control(["-m", "window", "\(id)", minimized ? "--minimize" : "--deminimize"])
        }
    }

    public func setFullscreen(_ id: Int, _ fullscreen: Bool) throws {
        let windows = try queryWindows()
        guard let current = windows.first(where: { $0.id == id }) else { return }
        if current.isNativeFullscreen != fullscreen {
            try control(["-m", "window", "\(id)", "--toggle", "native-fullscreen"])
        }
    }

    private func control(_ args: [String]) throws {
        let result = try runner.run(executable, args)
        guard result.succeeded else {
            throw CommandError.nonZeroExit(command: ([executable] + args).joined(separator: " "), result: result)
        }
    }
}

public enum YabaiError: Error, CustomStringConvertible {
    case invalidOutput(command: String)
    case decodeFailed(command: String, underlying: Error)

    public var description: String {
        switch self {
        case let .invalidOutput(command):
            return "yabai `\(command)` returned non-UTF8 output"
        case let .decodeFailed(command, underlying):
            return "could not decode yabai `\(command)` output: \(underlying)"
        }
    }
}
