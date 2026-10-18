import Foundation
import MacFanKit
import os

let logger = Logger(subsystem: "com.foxode.MacFan.FanHelper", category: "FanControl")

/// Applies the app's fan settings every second, and hands the fans back to macOS whenever the app goes away or
/// anything fails. All state is confined to `queue`.
final class FanControlService: NSObject, FanHelperProtocol, @unchecked Sendable {
    private static let interval: TimeInterval = 1
    /// A new target is written only when it differs from the last one by at least this many rpm.
    private static let minimumChange: Double = 25

    private struct Hardware {
        let smc: AppleSMC
        let fans: FanController
        let sensors: TemperatureSensors
    }

    private let queue = DispatchQueue(label: "com.foxode.MacFan.FanHelper.control")
    private var hardware: Hardware?
    private var configuration = FanControlConfiguration()
    /// The rpm last written to each fan MacFan is holding; empty while macOS controls the fans.
    private var lastTargets: [Int: Double] = [:]
    private var failure: String?
    private var timer: DispatchSourceTimer?
    private var connectionCount = 0

    override init() {
        super.init()
        // A previous helper process may have died while holding the fans.
        queue.sync { release() }
    }

    func apply(configuration data: Data, reply: @escaping @Sendable (String?) -> Void) {
        queue.async {
            guard let configuration = try? JSONDecoder().decode(FanControlConfiguration.self, from: data),
                configuration.isValid
            else {
                reply("invalid fan settings")
                return
            }
            logger.info("settings received: \(configuration.mode.rawValue, privacy: .public)")
            self.configuration = configuration
            self.failure = nil
            self.update()
            self.setTimerRunning(configuration.mode == .custom)
            reply(self.failure)
        }
    }

    func lastError(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { reply(self.failure) }
    }

    func connectionOpened() {
        queue.async { self.connectionCount += 1 }
    }

    /// The app's connection closes when it quits or crashes. With no app left, the fans go back to macOS and the
    /// helper exits; launchd starts it again on the next connection, from the app's current copy of the helper.
    func connectionClosed() {
        queue.async {
            self.connectionCount -= 1
            guard self.connectionCount == 0 else { return }
            self.setTimerRunning(false)
            self.release()
            exit(0)
        }
    }

    func shutDown() {
        queue.sync {
            setTimerRunning(false)
            release()
        }
    }

    private func setTimerRunning(_ running: Bool) {
        timer?.cancel()
        timer = nil
        guard running else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        timer.setEventHandler { [weak self] in self?.update() }
        timer.resume()
        self.timer = timer
    }

    /// One control step: works out each fan's target from the current temperature and applies it. On any failure
    /// the fans go back to macOS, and control pauses until the app sends settings again.
    private func update() {
        guard failure == nil else { return }
        do {
            let hardware = try openHardware()
            let temperature = hardware.sensors.temperature(of: configuration.sensor, from: hardware.smc)
            let statuses = try (0..<hardware.fans.fanCount()).map { try hardware.fans.status(ofFan: $0) }
            let targets = statuses.map {
                configuration.target(
                    temperature: temperature, minimumRPM: $0.minimumRPM, maximumRPM: $0.maximumRPM,
                    engaged: !lastTargets.isEmpty)
            }
            if targets.contains(.automatic) {
                if !lastTargets.isEmpty { release() }
                return
            }
            for (status, target) in zip(statuses, targets) {
                guard case .rpm(let goal) = target else { continue }
                // Taking over from macOS starts at the higher of the fan's actual speed and macOS's own target, so
                // the fan never slows down at the handover even when macOS has just started speeding it up.
                let current = lastTargets[status.index] ?? max(status.actualRPM, status.targetRPM ?? 0)
                let rpm = min(
                    max(configuration.nextRPM(from: current, toward: goal, elapsed: Self.interval), status.minimumRPM),
                    status.maximumRPM)
                // Write again after macOS resets the mode (it does on wake), or when the speed moved enough.
                let lastTarget = lastTargets[status.index] ?? -.infinity
                if status.mode != .manual || abs(lastTarget - rpm) >= Self.minimumChange {
                    try hardware.fans.setManual(fan: status.index, rpm: rpm)
                    lastTargets[status.index] = rpm
                    logger.info("fan \(status.index, privacy: .public): \(Int(rpm), privacy: .public) rpm")
                }
            }
        } catch {
            failure = String(describing: error)
            logger.error("fan control stopped: \(String(describing: error), privacy: .public)")
            release()
        }
    }

    /// Hands every fan back to macOS.
    private func release() {
        if !lastTargets.isEmpty {
            logger.info("handing the fans back to macOS")
        }
        try? openHardware().fans.restoreAutomaticControl()
        lastTargets = [:]
    }

    private func openHardware() throws -> Hardware {
        if let hardware { return hardware }
        let smc = try AppleSMC()
        let opened = try Hardware(
            smc: smc, fans: FanController(smc: smc), sensors: TemperatureSensors.discover(in: smc))
        hardware = opened
        return opened
    }
}
