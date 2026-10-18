import Foundation
import MacFanKit

let usage = """
    usage: macfan <command> [arguments]

    Read (any user):
      fans                        speed, range and mode of each fan
      temps                       temperature sensors (every T* key with a plausible value)
      read <KEY>...               raw SMC keys, e.g. `macfan read F0Ac F0Md`
      keys [PREFIX]               every SMC key, or only those starting with PREFIX

    Write (root):
      test <fan> <rpm> [seconds]  hold <rpm> for a while (default 20 s), then restore automatic control
      set <fan> <rpm>             leave a fan in manual mode at <rpm> until `macfan auto`
      auto                        return all fans to automatic control
    """

struct CommandError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func run(_ arguments: [String]) throws {
    guard let command = arguments.first, !["help", "-h", "--help"].contains(command) else {
        print(usage)
        return
    }
    let operands = Array(arguments.dropFirst())
    let smc = try AppleSMC()
    let fans = FanController(smc: smc)

    switch command {
    case "fans":
        let count = try fans.fanCount()
        if count == 0 {
            print("This Mac reports no fans.")
        }
        for index in 0..<count {
            print(try fans.status(ofFan: index).summary)
        }

    case "temps":
        for reading in try smc.temperatures() {
            print("\(reading.key)  \(String(format: "%5.1f", reading.celsius)) °C")
        }

    case "read":
        guard !operands.isEmpty else { throw CommandError("usage: macfan read <KEY>...") }
        for key in try operands.map(parseKey) {
            printValue(of: key, from: smc)
        }

    case "keys":
        let prefix = operands.first ?? ""
        for key in try smc.allKeys() where key.description.hasPrefix(prefix) {
            printValue(of: key, from: smc)
        }

    case "test":
        try requireRoot()
        guard operands.count == 2 || operands.count == 3 else {
            throw CommandError("usage: macfan test <fan> <rpm> [seconds]")
        }
        let seconds = try operands.count == 3 ? parseInteger(operands[2], name: "seconds", in: 1...600) : 20
        try runTest(
            fans, fan: parseInteger(operands[0], name: "fan", in: 0...9), rpm: parseRPM(operands[1]),
            seconds: seconds)

    case "set":
        try requireRoot()
        guard operands.count == 2 else { throw CommandError("usage: macfan set <fan> <rpm>") }
        let fan = try parseInteger(operands[0], name: "fan", in: 0...9)
        try fans.setManual(fan: fan, rpm: parseRPM(operands[1]), log: { print("  \($0)") })
        print(try fans.status(ofFan: fan).summary)
        print("Fan \(fan) stays in manual mode until you run `sudo macfan auto`.")

    case "auto":
        try requireRoot()
        try fans.restoreAutomaticControl()
        print("All fans are under automatic control.")

    default:
        throw CommandError("unknown command '\(command)'\n\n\(usage)")
    }
}

/// Holds `rpm` while printing the fan's response once a second, then always hands the fans back to
/// the system — also when interrupted with Ctrl-C.
func runTest(_ fans: FanController, fan: Int, rpm: Double, seconds: Int) throws {
    print("before  \(try fans.status(ofFan: fan).summary)")
    StopSignal.install()
    var failure: (any Error)?
    do {
        try fans.setManual(fan: fan, rpm: rpm, log: { print("  \($0)") })
        for second in 1...seconds {
            StopSignal.sleep(seconds: 1)
            if StopSignal.received {
                print("interrupted")
                break
            }
            let elapsed = "\(second)s".padding(toLength: 8, withPad: " ", startingAt: 0)
            print(elapsed + (try fans.status(ofFan: fan).summary))
        }
    } catch {
        failure = error
    }
    do {
        try fans.restoreAutomaticControl()
    } catch {
        throw CommandError("could not restore automatic control (\(error)); run `sudo macfan auto`")
    }
    print("automatic control restored")
    StopSignal.sleep(seconds: 3)
    print("after   \(try fans.status(ofFan: fan).summary)")
    if let failure { throw failure }
}

func requireRoot() throws {
    guard geteuid() == 0 else { throw CommandError("this command writes to the SMC and must be run with sudo") }
}

func parseKey(_ text: String) throws -> SMCKey {
    guard let key = SMCKey(text) else { throw CommandError("'\(text)' is not a four-character SMC key") }
    return key
}

func parseInteger(_ text: String, name: String, in range: ClosedRange<Int>) throws -> Int {
    guard let value = Int(text), range.contains(value) else {
        throw CommandError("\(name) must be a whole number from \(range.lowerBound) to \(range.upperBound)")
    }
    return value
}

func parseRPM(_ text: String) throws -> Double {
    guard let rpm = Double(text), rpm.isFinite else { throw CommandError("rpm must be a number") }
    return rpm
}

/// Prints one key as `KEY  type  number  [hex bytes]`, or the error if it cannot be read.
func printValue(of key: SMCKey, from smc: AppleSMC) {
    do {
        let value = try smc.read(key)
        let number = value.number.map { String(format: "%.2f", $0) } ?? "-"
        let hex = value.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("\(value.key)  \(value.type)  \(number)  [\(hex)]")
    } catch {
        print(error)
    }
}

func formatRPM(_ rpm: Double) -> String {
    String(format: "%.0f", rpm)
}

extension FanStatus {
    var summary: String {
        let target = targetRPM.map(formatRPM) ?? "-"
        let mode = mode.map { "\($0)" } ?? "-"
        return "fan \(index): \(formatRPM(actualRPM)) rpm  "
            + "(target \(target), range \(formatRPM(minimumRPM))–\(formatRPM(maximumRPM)), mode \(mode))"
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("macfan: \(error)\n".utf8))
    exit(1)
}
