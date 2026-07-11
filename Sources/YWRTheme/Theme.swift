import Foundation

// Implemented via ollama gemma4:31b, reviewed and integrated with one fix:
//   - added a public init to RGBAColor so it can be constructed in tests.
//
// Foundation-only theming schema. Colors are hex strings and fonts are named,
// so the whole theme can live in an external JSON file loaded at runtime. The
// SwiftUI mapping to Color/Font lives in the menu-bar app target.

public struct ColorPalette: Codable, Equatable, Sendable {
    public let accent: String
    public let background: String
    public let surface: String
    public let textPrimary: String
    public let textSecondary: String
    public let success: String
    public let warning: String
    public let error: String

    public init(accent: String, background: String, surface: String, textPrimary: String, textSecondary: String, success: String, warning: String, error: String) {
        self.accent = accent
        self.background = background
        self.surface = surface
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.success = success
        self.warning = warning
        self.error = error
    }
}

public struct FontStyle: Codable, Equatable, Sendable {
    public let family: String
    public let regularSize: Double
    public let titleSize: Double
    public let monospacedDigits: Bool

    public init(family: String, regularSize: Double, titleSize: Double, monospacedDigits: Bool) {
        self.family = family
        self.regularSize = regularSize
        self.titleSize = titleSize
        self.monospacedDigits = monospacedDigits
    }
}

public struct ThemeConfig: Codable, Equatable, Sendable {
    public let colors: ColorPalette
    public let font: FontStyle

    public init(colors: ColorPalette, font: FontStyle) {
        self.colors = colors
        self.font = font
    }

    public static let `default` = ThemeConfig(
        colors: ColorPalette(
            accent: "#4C8DFF",
            background: "#1E1E1E",
            surface: "#2A2A2A",
            textPrimary: "#FFFFFF",
            textSecondary: "#A0A0A0",
            success: "#3FB950",
            warning: "#D29922",
            error: "#F85149"
        ),
        font: FontStyle(
            family: "System",
            regularSize: 13,
            titleSize: 15,
            monospacedDigits: true
        )
    )
}

public struct RGBAColor: Equatable, Sendable {
    public let red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public enum ThemeError: Error, CustomStringConvertible {
    case invalidHex(String)

    public var description: String {
        switch self {
        case .invalidHex(let hex):
            return "The provided string '\(hex)' is not a valid 6 or 8 digit hexadecimal color."
        }
    }
}

public enum HexColor {
    public static func parse(_ hex: String) throws -> RGBAColor {
        var cleaned = hex
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        let length = cleaned.count
        guard (length == 6 || length == 8),
              cleaned.allSatisfy({ $0.isHexDigit }) else {
            throw ThemeError.invalidHex(hex)
        }

        let scanner = Scanner(string: cleaned)
        var hexValue: UInt64 = 0
        guard scanner.scanHexInt64(&hexValue) else {
            throw ThemeError.invalidHex(hex)
        }

        let r, g, b, a: Double
        if length == 6 {
            r = Double((hexValue >> 16) & 0xFF) / 255.0
            g = Double((hexValue >> 8) & 0xFF) / 255.0
            b = Double(hexValue & 0xFF) / 255.0
            a = 1.0
        } else {
            r = Double((hexValue >> 24) & 0xFF) / 255.0
            g = Double((hexValue >> 16) & 0xFF) / 255.0
            b = Double((hexValue >> 8) & 0xFF) / 255.0
            a = Double(hexValue & 0xFF) / 255.0
        }

        return RGBAColor(red: r, green: g, blue: b, alpha: a)
    }
}

public protocol ThemeProviding: Sendable {
    func load() -> ThemeConfig
}

public struct ThemeLoader: ThemeProviding {
    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public func load() -> ThemeConfig {
        guard let url = url else {
            return .default
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(ThemeConfig.self, from: data)
        } catch {
            return .default
        }
    }
}
