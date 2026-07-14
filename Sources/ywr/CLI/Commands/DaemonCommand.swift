import Foundation
import YWRCore

/// `ywr daemon` runs a foreground polling loop: whenever the display
/// configuration changes, it auto-restores the best-matching snapshot.
struct DaemonCommand: Command {
    let name = "daemon"
    let summary = "Watch for display changes and auto-restore layouts"
    var usage: String { "ywr daemon [--interval <seconds>]" }

    private let monitorFactory: (Double) -> DisplayMonitor

    /// The monitor is built lazily from the poll interval so the interval can
    /// come from the command line while dependencies stay injected.
    init(monitorFactory: @escaping (Double) -> DisplayMonitor) {
        self.monitorFactory = monitorFactory
    }

    func run(_ args: [String]) throws -> Int32 {
        let interval = try parseInterval(args)
        let monitor = monitorFactory(interval)
        print("ywr daemon started (polling every \(interval)s). Press Ctrl-C to stop.")
        // Runs until interrupted; iterations: nil = loop forever. The loop
        // absorbs transient poll failures internally, so it never returns early.
        monitor.poll(iterations: nil, startingFingerprint: nil)
        return 0
    }

    private func parseInterval(_ args: [String]) throws -> Double {
        guard let idx = args.firstIndex(of: "--interval") else { return 2.0 }
        guard idx + 1 < args.count, let value = Double(args[idx + 1]), value > 0 else {
            throw CLIError.usage(usage)
        }
        return value
    }
}
