import Foundation

/// The SMC's per-fan mode key. Apple silicon uses 0 for automatic and 1 for manual; other values have
/// been reported on some chips and are kept verbatim.
public enum FanMode: Equatable, Sendable, CustomStringConvertible {
    case automatic
    case manual
    case other(Int)

    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .automatic
        case 1: self = .manual
        default: self = .other(rawValue)
        }
    }

    var rawValue: Int {
        switch self {
        case .automatic: 0
        case .manual: 1
        case .other(let value): value
        }
    }

    public var description: String {
        switch self {
        case .automatic: "auto"
        case .manual: "manual"
        case .other(let value): "other(\(value))"
        }
    }
}

public struct FanStatus: Equatable, Sendable {
    public let index: Int
    public let actualRPM: Double
    public let minimumRPM: Double
    public let maximumRPM: Double
    public let targetRPM: Double?
    /// `nil` when the Mac has no per-fan mode key, as on Intel Macs.
    public let mode: FanMode?
}

public enum FanControlError: Error, Equatable, CustomStringConvertible {
    case noSuchFan(Int, fanCount: Int)
    case speedOutOfRange(rpm: Double, minimum: Double, maximum: Double)
    /// No per-fan mode key. Intel Macs control fans differently, which MacFan does not implement yet.
    case manualModeUnsupported(fan: Int)
    /// The SMC kept refusing manual mode, even after setting `Ftst` where that key exists.
    case manualModeRejected(fan: Int)

    public var description: String {
        switch self {
        case .noSuchFan(let index, let count):
            "there is no fan \(index); this Mac has \(count)"
        case .speedOutOfRange(let rpm, let minimum, let maximum):
            String(format: "%.0f rpm is outside the fan's range (%.0f–%.0f rpm)", rpm, minimum, maximum)
        case .manualModeUnsupported(let fan):
            "fan \(fan) has no mode key; manual control is only implemented for Apple silicon"
        case .manualModeRejected(let fan):
            "the SMC refused to put fan \(fan) into manual mode"
        }
    }
}

/// Reads fan state and moves fans between automatic and manual control.
///
/// On Apple silicon, writing 1 to the fan's mode key hands it to manual control and `F<n>Tg` sets its
/// target speed. The mode key is `F<n>Md` on earlier chips and `F<n>md` on an M5 Pro running macOS 27, where this
/// was verified.
/// Some chips reject the mode change while macOS's thermal daemon owns the fans; where the undocumented
/// `Ftst` key exists, writing 1 to it first releases them. None of this is documented by Apple — it comes
/// from community reverse engineering and testing — so mode changes are verified by reading the key back.
public struct FanController {
    private let smc: any SMCDevice
    private let unlockAttempts: Int
    private let retryInterval: TimeInterval
    private let sleep: (TimeInterval) -> Void

    public init(
        smc: any SMCDevice,
        unlockAttempts: Int = 20,
        retryInterval: TimeInterval = 0.5,
        sleep: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) {
        self.smc = smc
        self.unlockAttempts = unlockAttempts
        self.retryInterval = retryInterval
        self.sleep = sleep
    }

    /// Number of fans; 0 on fanless Macs.
    public func fanCount() throws -> Int {
        do {
            return try Int(smc.readNumber(.fanCount))
        } catch let error as SMCError where error.isKeyNotFound {
            return 0
        }
    }

    public func status(ofFan index: Int) throws -> FanStatus {
        try checkFanExists(index)
        return try FanStatus(
            index: index,
            actualRPM: smc.readNumber(.fan(index, "Ac")),
            minimumRPM: smc.readNumber(.fan(index, "Mn")),
            maximumRPM: smc.readNumber(.fan(index, "Mx")),
            targetRPM: try? smc.readNumber(.fan(index, "Tg")),
            mode: modeKey(ofFan: index).flatMap { try? mode(at: $0) }
        )
    }

    /// Puts a fan under manual control at `rpm`, which must lie within the fan's own min–max range.
    /// `log` receives a line for each fallback step, for diagnostics.
    public func setManual(fan index: Int, rpm: Double, log: (String) -> Void = { _ in }) throws {
        let status = try status(ofFan: index)
        guard rpm >= status.minimumRPM, rpm <= status.maximumRPM else {
            throw FanControlError.speedOutOfRange(
                rpm: rpm, minimum: status.minimumRPM, maximum: status.maximumRPM)
        }
        guard let modeKey = modeKey(ofFan: index), let mode = status.mode else {
            throw FanControlError.manualModeUnsupported(fan: index)
        }
        if mode != .manual {
            try enterManualMode(modeKey, fan: index, previousMode: mode, log: log)
        }
        try smc.writeNumber(rpm, to: .fan(index, "Tg"))
    }

    /// Hands every fan that is in manual mode back to the system and clears `Ftst`. Fans in any other
    /// mode are left untouched. Every step is attempted; the first failure is rethrown afterwards.
    public func restoreAutomaticControl() throws {
        var firstError: (any Error)?
        let count = try fanCount()
        for index in 0..<count {
            guard let modeKey = modeKey(ofFan: index), (try? mode(at: modeKey)) == .manual else { continue }
            do {
                try smc.writeNumber(0, to: modeKey)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let unlocked = try? smc.readNumber(.fanTestMode), unlocked != 0 {
            do {
                try smc.writeNumber(0, to: .fanTestMode)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    private func enterManualMode(
        _ modeKey: SMCKey, fan index: Int, previousMode: FanMode, log: (String) -> Void
    ) throws {
        do {
            try smc.writeNumber(1, to: modeKey)
            let mode = try mode(at: modeKey)
            if mode == .manual { return }
            log("\(modeKey)=1 was accepted, but the fan reports \(mode)")
        } catch let error as SMCError where !error.isNotPrivileged {
            log("\(modeKey)=1 failed: \(error)")
        }

        if smc.hasKey(.fanTestMode) {
            log("setting Ftst=1 and retrying")
            do {
                try smc.writeNumber(1, to: .fanTestMode)
                for _ in 0..<unlockAttempts {
                    sleep(retryInterval)
                    if (try? smc.writeNumber(1, to: modeKey)) != nil, (try? mode(at: modeKey)) == .manual {
                        return
                    }
                }
            } catch {
                log("Ftst=1 failed: \(error)")
            }
            try? smc.writeNumber(0, to: .fanTestMode)
        }
        // Undo whatever the attempts above may have left in the mode key.
        try? smc.writeNumber(Double(previousMode.rawValue), to: modeKey)
        throw FanControlError.manualModeRejected(fan: index)
    }

    private func modeKey(ofFan index: Int) -> SMCKey? {
        [SMCKey.fan(index, "Md"), .fan(index, "md")].first { smc.hasKey($0) }
    }

    private func mode(at key: SMCKey) throws -> FanMode {
        try FanMode(rawValue: Int(smc.readNumber(key)))
    }

    private func checkFanExists(_ index: Int) throws {
        let count = try fanCount()
        guard (0..<count).contains(index) else { throw FanControlError.noSuchFan(index, fanCount: count) }
    }
}
