import IOKit

public struct TemperatureReading: Equatable, Sendable {
    public let key: SMCKey
    public let celsius: Double
}

/// Connection to the AppleSMC IOKit service. Reading works for any user; writing requires root.
public final class AppleSMC: SMCDevice {
    private var connection: io_connect_t = 0
    /// A key's size and type never change, so each is fetched once; this halves the calls per read.
    private var keyInfoCache: [SMCKey: SMCKeyInfo] = [:]

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    }

    deinit {
        IOServiceClose(connection)
    }

    public func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        if let cached = keyInfoCache[key] { return cached }
        var input = SMCParamStruct()
        input.key = key.code
        input.data8 = SMCParamStruct.Command.keyInfo
        let output = try call(input, key: key).keyInfo
        let info = SMCKeyInfo(
            size: Int(output.dataSize), type: output.dataType.fourCharacters, attributes: output.dataAttributes)
        keyInfoCache[key] = info
        return info
    }

    public func read(_ key: SMCKey) throws -> SMCValue {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = SMCParamStruct.Command.readKey
        let output = try call(input, key: key)
        return SMCValue(key: key, type: info.type, bytes: Array(output.data.prefix(info.size)))
    }

    public func write(_ key: SMCKey, bytes: [UInt8]) throws {
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.data8 = SMCParamStruct.Command.writeKey
        input.data = bytes
        _ = try call(input, key: key)
    }

    /// Number of keys the SMC exposes (`#KEY`).
    public func keyCount() throws -> Int {
        try Int(readNumber(.keyCount))
    }

    public func key(at index: Int) throws -> SMCKey {
        var input = SMCParamStruct()
        input.data8 = SMCParamStruct.Command.keyFromIndex
        input.data32 = UInt32(index)
        return try SMCKey(code: call(input, key: nil).key)
    }

    public func allKeys() throws -> [SMCKey] {
        try (0..<keyCount()).map(key(at:))
    }

    /// Every `T…` key holding a plausible Celsius value. Sensor names differ between Apple silicon
    /// generations, so this scans the key list instead of relying on a fixed table.
    public func temperatures() throws -> [TemperatureReading] {
        try allKeys().compactMap { key in
            guard key.description.hasPrefix("T"),
                let celsius = try? read(key).number,
                isPlausibleTemperature(celsius)
            else { return nil }
            return TemperatureReading(key: key, celsius: celsius)
        }
    }

    private func call(_ input: SMCParamStruct, key: SMCKey?) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, SMCParamStruct.handleYPCEvent,
            &input, MemoryLayout<SMCParamStruct>.stride,
            &output, &outputSize)
        guard result == kIOReturnSuccess else { throw SMCError.ioKit(key, result) }
        guard output.result == SMCParamStruct.success else { throw SMCError.smc(key, output.result) }
        return output
    }
}
