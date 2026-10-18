@testable import MacFanKit

/// In-memory SMC for exercising `FanController` without hardware.
final class FakeSMC: SMCDevice {
    private var values: [SMCKey: SMCValue] = [:]
    private(set) var writtenKeys: [SMCKey] = []
    /// Runs before every write and returns the bytes to store. Throw from it to simulate the SMC rejecting
    /// the write, or return other bytes to simulate a write that does not stick.
    var onWrite: (SMCKey, [UInt8]) throws -> [UInt8] = { $1 }

    /// One Apple silicon-style fan in automatic mode, with `Ftst` cleared.
    static func appleSiliconMac() -> FakeSMC {
        let smc = FakeSMC()
        smc.set("FNum", "ui8 ", 1)
        smc.set("F0Ac", "flt ", 1200)
        smc.set("F0Mn", "flt ", 1000)
        smc.set("F0Mx", "flt ", 4900)
        smc.set("F0Tg", "flt ", 1200)
        smc.set("F0Md", "ui8 ", 0)
        smc.set("Ftst", "ui8 ", 0)
        return smc
    }

    /// Key layout read from an M5 Pro Mac mini on macOS 27: lowercase `F0md` and no `Ftst`.
    static func m5Mac() -> FakeSMC {
        let smc = appleSiliconMac()
        smc.remove("F0Md")
        smc.remove("Ftst")
        smc.set("F0md", "ui8 ", 0)
        return smc
    }

    func set(_ key: SMCKey, _ type: String, _ number: Double) {
        let size = ["flt ": 4, "ui8 ": 1, "fpe2": 2][type]!
        values[key] = SMCValue(key: key, type: type, bytes: SMCCodec.encode(number, type: type, size: size)!)
    }

    func remove(_ key: SMCKey) {
        values[key] = nil
    }

    func number(_ key: SMCKey) -> Double? {
        values[key]?.number
    }

    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        let value = try read(key)
        return SMCKeyInfo(size: value.bytes.count, type: value.type, attributes: 0)
    }

    func read(_ key: SMCKey) throws -> SMCValue {
        guard let value = values[key] else { throw SMCError.smc(key, SMCError.keyNotFound) }
        return value
    }

    func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let current = try read(key)
        let stored = try onWrite(key, bytes)
        writtenKeys.append(key)
        values[key] = SMCValue(key: key, type: current.type, bytes: stored)
    }
}
