/// Size, data type and attribute flags the SMC reports for a key.
public struct SMCKeyInfo: Equatable, Sendable {
    public let size: Int
    public let type: String
    public let attributes: UInt8

    public init(size: Int, type: String, attributes: UInt8) {
        self.size = size
        self.type = type
        self.attributes = attributes
    }
}

/// Reads and writes SMC keys. `AppleSMC` is the hardware implementation; tests use a fake.
public protocol SMCDevice {
    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo
    func read(_ key: SMCKey) throws -> SMCValue
    func write(_ key: SMCKey, bytes: [UInt8]) throws
}

extension SMCDevice {
    public func hasKey(_ key: SMCKey) -> Bool {
        (try? keyInfo(key)) != nil
    }

    public func readNumber(_ key: SMCKey) throws -> Double {
        let value = try read(key)
        guard let number = value.number else { throw SMCError.unsupportedType(key, value.type) }
        return number
    }

    /// Encodes `number` in the key's own data type and writes it.
    public func writeNumber(_ number: Double, to key: SMCKey) throws {
        let info = try keyInfo(key)
        guard let bytes = SMCCodec.encode(number, type: info.type, size: info.size) else {
            throw SMCError.unencodable(key, number, type: info.type)
        }
        try write(key, bytes: bytes)
    }
}
