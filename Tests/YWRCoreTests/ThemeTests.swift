import XCTest
@testable import YWRTheme

final class ThemeTests: XCTestCase {
    func testParseSixDigitHex() throws {
        let c = try HexColor.parse("#4C8DFF")
        XCTAssertEqual(c.red, Double(0x4C) / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.green, Double(0x8D) / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.blue, 1.0, accuracy: 0.0001)
        XCTAssertEqual(c.alpha, 1.0, accuracy: 0.0001)
    }

    func testParseEightDigitHexWithAlpha() throws {
        let c = try HexColor.parse("FF000080")
        XCTAssertEqual(c.red, 1.0, accuracy: 0.0001)
        XCTAssertEqual(c.green, 0.0, accuracy: 0.0001)
        XCTAssertEqual(c.alpha, Double(0x80) / 255.0, accuracy: 0.0001)
    }

    func testParseWithoutLeadingHash() throws {
        let c = try HexColor.parse("000000")
        XCTAssertEqual(c.red, 0)
        XCTAssertEqual(c.blue, 0)
    }

    func testInvalidHexThrows() {
        XCTAssertThrowsError(try HexColor.parse("#12345"))   // wrong length
        XCTAssertThrowsError(try HexColor.parse("#GGGGGG"))  // non-hex
        XCTAssertThrowsError(try HexColor.parse(""))
    }

    func testDefaultThemeIsWellFormed() throws {
        let theme = ThemeConfig.default
        // Every palette color must parse.
        for hex in [theme.colors.accent, theme.colors.background, theme.colors.surface,
                    theme.colors.textPrimary, theme.colors.textSecondary,
                    theme.colors.success, theme.colors.warning, theme.colors.error] {
            XCTAssertNoThrow(try HexColor.parse(hex))
        }
        XCTAssertEqual(theme.font.family, "System")
    }

    func testLoaderReturnsDefaultWhenURLIsNil() {
        XCTAssertEqual(ThemeLoader(url: nil).load(), ThemeConfig.default)
    }

    func testLoaderReturnsDefaultOnMissingFile() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)/theme.json")
        XCTAssertEqual(ThemeLoader(url: missing).load(), ThemeConfig.default)
    }

    func testLoaderReadsCustomThemeFromFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("theme.json")

        let custom = ThemeConfig(
            colors: ColorPalette(accent: "#111111", background: "#222222", surface: "#333333",
                                 textPrimary: "#444444", textSecondary: "#555555",
                                 success: "#666666", warning: "#777777", error: "#888888"),
            font: FontStyle(family: "Menlo", regularSize: 12, titleSize: 14, monospacedDigits: false)
        )
        let data = try JSONEncoder().encode(custom)
        try data.write(to: url)

        let loaded = ThemeLoader(url: url).load()
        XCTAssertEqual(loaded, custom)
        XCTAssertEqual(loaded.font.family, "Menlo")
    }

    func testLoaderFallsBackOnCorruptJSON() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("theme.json")
        try Data("{ not valid json".utf8).write(to: url)

        XCTAssertEqual(ThemeLoader(url: url).load(), ThemeConfig.default)
    }
}
