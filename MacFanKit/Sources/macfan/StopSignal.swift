import Foundation

nonisolated(unsafe) private var stopRequested: sig_atomic_t = 0

/// Records SIGINT, SIGTERM and SIGHUP so `test` can restore automatic control before exiting.
enum StopSignal {
    static func install() {
        stopRequested = 0
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber) { _ in stopRequested = 1 }
        }
    }

    static var received: Bool {
        stopRequested != 0
    }

    /// Sleeps for `seconds`, waking early if a stop signal arrives.
    static func sleep(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while !received, Date() < deadline {
            usleep(50_000)
        }
    }
}
