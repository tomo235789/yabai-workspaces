import Foundation
import YWRTheme
import YWRMenuUI

// Headless screenshot tool. Renders the menu-bar UI in several states to PNG
// files so the test/report tooling has real screenshots without a GUI session.
//
// Usage: ywr-shot <output-dir>
// Exit code is non-zero if any required artifact could not be produced, so the
// report pipeline can reflect a failed screenshot stage.

@MainActor
func run() -> Int32 {
    let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
    do {
        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    } catch {
        FileHandle.standardError.write(Data("ywr-shot: cannot create \(outDir): \(error)\n".utf8))
        return 1
    }

    let theme = Theme(.default)
    let states: [(name: String, caption: String, snaps: [String], status: String, newName: String)] = [
        ("01-empty", "Initial state", [], "", ""),
        ("02-typing", "Naming a snapshot", [], "", "home"),
        ("03-saved", "After saving, with snapshots listed", ["home", "office", "cafe"], "Saved 'home'", ""),
        ("04-restored", "After auto-restore", ["home", "office", "cafe"], "Restored 'home': 12 moved, 0 failed", "")
    ]

    var manifest: [[String: String]] = []
    var failures = 0
    for s in states {
        let model = MenuViewModel(actions: StubActions(), snapshots: s.snaps, status: s.status, newName: s.newName)
        let file = "\(s.name).png"
        guard let png = MenuRenderer.png(model: model, theme: theme) else {
            FileHandle.standardError.write(Data("ywr-shot: render failed for \(s.name)\n".utf8))
            failures += 1
            continue
        }
        do {
            try png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(file))
            manifest.append(["file": file, "caption": s.caption])
            print("wrote \(file) (\(png.count) bytes)")
        } catch {
            FileHandle.standardError.write(Data("ywr-shot: cannot write \(file): \(error)\n".utf8))
            failures += 1
        }
    }

    // Only list images that were actually written.
    do {
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("manifest.json"))
    } catch {
        FileHandle.standardError.write(Data("ywr-shot: cannot write manifest: \(error)\n".utf8))
        failures += 1
    }

    return failures == 0 ? 0 : 1
}

exit(MainActor.assumeIsolated { run() })
