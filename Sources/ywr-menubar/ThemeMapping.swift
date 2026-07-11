import SwiftUI
import YWRTheme

// Implemented via ollama gemma4:31b, reviewed and integrated unchanged.
// Bridges the Foundation-only YWRTheme schema to SwiftUI Color/Font.

extension Color {
    init(_ rgba: RGBAColor) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    static func fromHex(_ hex: String, fallback: Color = .gray) -> Color {
        do {
            let rgba = try HexColor.parse(hex)
            return Color(rgba)
        } catch {
            return fallback
        }
    }
}

public struct Theme {
    public let config: ThemeConfig

    public init(_ config: ThemeConfig) {
        self.config = config
    }

    public var accent: Color { Color.fromHex(config.colors.accent) }
    public var background: Color { Color.fromHex(config.colors.background) }
    public var surface: Color { Color.fromHex(config.colors.surface) }
    public var textPrimary: Color { Color.fromHex(config.colors.textPrimary) }
    public var textSecondary: Color { Color.fromHex(config.colors.textSecondary) }
    public var success: Color { Color.fromHex(config.colors.success) }
    public var warning: Color { Color.fromHex(config.colors.warning) }
    public var error: Color { Color.fromHex(config.colors.error) }

    public var bodyFont: Font {
        let font: Font
        if config.font.family == "System" {
            font = .system(size: config.font.regularSize)
        } else {
            font = .custom(config.font.family, size: config.font.regularSize)
        }
        return config.font.monospacedDigits ? font.monospacedDigit() : font
    }

    public var titleFont: Font {
        let font: Font
        if config.font.family == "System" {
            font = .system(size: config.font.titleSize, weight: .semibold)
        } else {
            font = .custom(config.font.family, size: config.font.titleSize).weight(.semibold)
        }
        return config.font.monospacedDigits ? font.monospacedDigit() : font
    }
}
