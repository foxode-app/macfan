/// A four-character SMC key such as `F0Ac`, stored as the big-endian code the SMC uses.
public struct SMCKey: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let code: UInt32

    public init(code: UInt32) {
        self.code = code
    }

    /// Returns `nil` unless `string` is exactly four ASCII characters.
    public init?(_ string: String) {
        guard let code = UInt32(fourCharacters: string) else { return nil }
        self.code = code
    }

    public init(stringLiteral value: String) {
        guard let key = SMCKey(value) else {
            preconditionFailure("SMC keys are exactly four ASCII characters: \(value)")
        }
        self = key
    }

    public var description: String {
        code.fourCharacters
    }
}

extension SMCKey {
    static let keyCount: SMCKey = "#KEY"
    static let fanCount: SMCKey = "FNum"
    /// Undocumented "fan test" flag that releases the fans from macOS's thermal daemon on some chips.
    static let fanTestMode: SMCKey = "Ftst"

    /// Per-fan key, e.g. `fan(0, "Ac")` is `F0Ac`.
    static func fan(_ index: Int, _ suffix: String) -> SMCKey {
        precondition((0...9).contains(index), "fan index out of range: \(index)")
        let name = "F\(index)\(suffix)"
        guard let key = SMCKey(name) else { preconditionFailure("invalid fan key: \(name)") }
        return key
    }
}

extension UInt32 {
    init?(fourCharacters string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
        self = bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    var fourCharacters: String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: self >> $0) }, as: UTF8.self)
    }
}
