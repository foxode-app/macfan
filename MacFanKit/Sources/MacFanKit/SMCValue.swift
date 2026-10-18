/// The raw bytes of an SMC key together with the data type the SMC reported for it.
public struct SMCValue: Equatable, Sendable {
    public let key: SMCKey
    /// Four-character SMC type code, such as `flt ` or `ui8 `.
    public let type: String
    public let bytes: [UInt8]

    public init(key: SMCKey, type: String, bytes: [UInt8]) {
        self.key = key
        self.type = type
        self.bytes = bytes
    }

    /// The value as a number, or `nil` if MacFan cannot decode the type.
    public var number: Double? {
        SMCCodec.decode(bytes, type: type)
    }
}

/// Converts between numbers and the SMC's data types.
///
/// Integer and fixed-point types are big-endian. `flt ` is a native little-endian `Float`, which is
/// what Apple silicon uses for fan speeds and temperatures.
enum SMCCodec {
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch (type, bytes.count) {
        case ("flt ", 4):
            return Double(Float(bitPattern: UInt32(readLittleEndian(bytes))))
        case ("ui8 ", 1), ("flag", 1), ("ui16", 2), ("ui32", 4):
            return Double(readBigEndian(bytes))
        case ("si8 ", 1):
            return Double(Int8(bitPattern: bytes[0]))
        case ("si16", 2):
            return Double(Int16(bitPattern: UInt16(readBigEndian(bytes))))
        case ("si32", 4):
            return Double(Int32(bitPattern: UInt32(readBigEndian(bytes))))
        case (_, 2):
            guard let format = FixedPoint(type) else { return nil }
            let raw = UInt16(readBigEndian(bytes))
            return (format.isSigned ? Double(Int16(bitPattern: raw)) : Double(raw)) / format.scale
        default:
            return nil
        }
    }

    /// Encodes `number` as `type`, or returns `nil` if it does not fit.
    static func encode(_ number: Double, type: String, size: Int) -> [UInt8]? {
        switch (type, size) {
        case ("flt ", 4):
            let float = Float(number)
            guard float.isFinite else { return nil }
            return littleEndianBytes(UInt64(float.bitPattern), count: 4)
        case ("ui8 ", 1), ("flag", 1), ("ui16", 2), ("ui32", 4):
            guard let raw = UInt64(exactly: number), raw >> (size * 8) == 0 else { return nil }
            return bigEndianBytes(raw, count: size)
        case (_, 2):
            guard let format = FixedPoint(type) else { return nil }
            let scaled = (number * format.scale).rounded()
            if format.isSigned {
                guard let raw = Int16(exactly: scaled) else { return nil }
                return bigEndianBytes(UInt64(UInt16(bitPattern: raw)), count: 2)
            }
            guard let raw = UInt16(exactly: scaled) else { return nil }
            return bigEndianBytes(UInt64(raw), count: 2)
        default:
            return nil
        }
    }

    private static func readBigEndian(_ bytes: [UInt8]) -> UInt64 {
        bytes.reduce(0) { $0 << 8 | UInt64($1) }
    }

    private static func readLittleEndian(_ bytes: [UInt8]) -> UInt64 {
        readBigEndian(bytes.reversed())
    }

    private static func bigEndianBytes(_ value: UInt64, count: Int) -> [UInt8] {
        (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    private static func littleEndianBytes(_ value: UInt64, count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
}

/// `fpXY` (unsigned) and `spXY` (signed) 16-bit fixed-point types, where the hex digits X and Y count
/// integer and fraction bits: `fpe2` is 14.2, `sp78` is a sign bit plus 7.8.
private struct FixedPoint {
    let isSigned: Bool
    let scale: Double

    init?(_ type: String) {
        let characters = Array(type)
        guard characters.count == 4, type.hasPrefix("fp") || type.hasPrefix("sp"),
            let integerBits = characters[2].hexDigitValue,
            let fractionBits = characters[3].hexDigitValue
        else { return nil }
        isSigned = type.hasPrefix("sp")
        guard integerBits + fractionBits == (isSigned ? 15 : 16) else { return nil }
        scale = Double(1 << fractionBits)
    }
}
