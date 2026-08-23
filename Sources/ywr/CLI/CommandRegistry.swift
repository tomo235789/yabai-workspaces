import Foundation
import YWRCore

/// Dispatches the top-level argument to a registered command. Holds command
/// instances so the concrete wiring lives entirely in the composition root.
struct CommandRegistry {
    private let commands: [Command]

    init(commands: [Command]) {
        self.commands = commands
    }

    func command(named name: String) -> Command? {
        commands.first { $0.name == name }
    }

    /// Runs argv (excluding the program name). Returns an exit code.
    func run(_ argv: [String]) -> Int32 {
        guard let first = argv.first else {
            printHelp()
            return 1
        }
        if first == "-h" || first == "--help" || first == "help" {
            printHelp()
            return 0
        }
        if first == "-v" || first == "--version" || first == "version" {
            print("ywr \(YWRVersion.current)")
            return 0
        }
        guard let command = command(named: first) else {
            FileHandle.standardError.write(Data("error: unknown command '\(first)'\n\n".utf8))
            printHelp()
            return 1
        }
        do {
            return try command.run(Array(argv.dropFirst()))
        } catch let error as CLIError {
            switch error {
            case let .usage(text):
                FileHandle.standardError.write(Data("usage: \(text)\n".utf8))
            case let .message(text):
                FileHandle.standardError.write(Data("error: \(text)\n".utf8))
            }
            return 1
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }

    func printHelp() {
        var lines = ["ywr — yabai workspaces: save & restore window layouts", "", "USAGE:", "  ywr <command> [options]", "", "COMMANDS:"]
        let width = commands.map(\.name.count).max() ?? 0
        for c in commands {
            lines.append("  \(c.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(c.summary)")
        }
        lines.append("")
        print(lines.joined(separator: "\n"))
    }
}
