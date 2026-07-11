import Foundation

// Implemented via ollama gemma4:31b, reviewed and integrated unchanged.
// Polls the display configuration; on a fingerprint change it invokes a
// handler (wired to `restore --auto`). No GCD — the loop is driven by an
// injected Waiter so tests can run a bounded number of iterations instantly.

// Not Sendable: the daemon runs on a single foreground thread, and concrete
// handlers legitimately hold non-Sendable collaborators (e.g. SnapshotStore).
public protocol DisplayChangeHandling {
    func handleChange(from oldFingerprint: String?, to newFingerprint: String)
}

public protocol DisplayWatching: Sendable {
    func runOnce(previousFingerprint: String?) throws -> String
}

public struct DisplayWatcher: DisplayWatching {
    private let yabai: YabaiQuerying
    private let fingerprint: FingerprintGenerating

    public init(yabai: YabaiQuerying, fingerprint: FingerprintGenerating = DefaultFingerprintGenerator()) {
        self.yabai = yabai
        self.fingerprint = fingerprint
    }

    public func runOnce(previousFingerprint: String?) throws -> String {
        let displays = try yabai.queryDisplays()
        return fingerprint.fingerprint(for: displays)
    }
}

public struct DisplayMonitor {
    private let watcher: DisplayWatching
    private let handler: DisplayChangeHandling
    private let waiter: Waiter
    private let pollInterval: Double
    private let logger: any EventLogging

    public init(
        watcher: DisplayWatching,
        handler: DisplayChangeHandling,
        waiter: Waiter = RealWaiter(),
        pollInterval: Double = 2.0,
        logger: any EventLogging = ConsoleLogger()
    ) {
        self.watcher = watcher
        self.handler = handler
        self.waiter = waiter
        self.pollInterval = pollInterval
        self.logger = logger
    }

    public func poll(iterations: Int? = nil, startingFingerprint: String? = nil) {
        var current = startingFingerprint
        var count = 0

        while true {
            if let iterations = iterations, count >= iterations {
                break
            }

            // A transient query failure (e.g. yabai restarting) must NOT kill a
            // long-running daemon: log it and keep polling.
            do {
                let fp = try watcher.runOnce(previousFingerprint: current)
                if fp != current {
                    handler.handleChange(from: current, to: fp)
                    current = fp
                }
            } catch {
                logger.log("Poll failed (will retry): \(error)")
            }

            waiter.wait(seconds: pollInterval)
            count += 1
        }
    }
}
