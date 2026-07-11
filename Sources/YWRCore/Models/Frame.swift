import Foundation

/// A rectangle in absolute (global) screen coordinates, matching yabai's
/// `frame` object.
public struct Frame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

/// A rectangle expressed as fractions (0.0...1.0) of a display's frame.
///
/// Storing this alongside the absolute `Frame` is what lets restore survive a
/// change in the target display's resolution or position — the plan explicitly
/// forbids saving absolute coordinates only.
public struct RelativeFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    /// Projects a window frame into the coordinate space of `display`.
    public static func within(_ display: Frame, window: Frame) -> RelativeFrame {
        let safeW = display.w == 0 ? 1 : display.w
        let safeH = display.h == 0 ? 1 : display.h
        return RelativeFrame(
            x: (window.x - display.x) / safeW,
            y: (window.y - display.y) / safeH,
            w: window.w / safeW,
            h: window.h / safeH
        )
    }

    /// Resolves this relative frame back to absolute coordinates on `display`.
    public func resolved(on display: Frame) -> Frame {
        Frame(
            x: display.x + x * display.w,
            y: display.y + y * display.h,
            w: w * display.w,
            h: h * display.h
        )
    }
}
