import Darwin

public enum SMCError: Error, Equatable, CustomStringConvertible {
    case serviceNotFound
    case openFailed(kern_return_t)
    /// `IOConnectCallStructMethod` failed, e.g. with `kIOReturnNotPrivileged` when writing without root.
    case ioKit(SMCKey?, kern_return_t)
    /// The SMC answered with a non-zero result code, e.g. 0x84 for a missing key.
    case smc(SMCKey?, UInt8)
    case unsupportedType(SMCKey, String)
    case unencodable(SMCKey, Double, type: String)

    static let keyNotFound: UInt8 = 0x84
    static let notPrivileged = kern_return_t(bitPattern: 0xE000_02C1)

    public var isKeyNotFound: Bool {
        if case .smc(_, Self.keyNotFound) = self { true } else { false }
    }

    public var isNotPrivileged: Bool {
        if case .ioKit(_, Self.notPrivileged) = self { true } else { false }
    }

    public var description: String {
        switch self {
        case .serviceNotFound:
            "AppleSMC service not found"
        case .openFailed(let code):
            "cannot open AppleSMC: \(Self.describe(code))"
        case .ioKit(let key, let code):
            Self.prefix(key) + Self.describe(code)
        case .smc(let key, let code):
            Self.prefix(key) + "SMC error 0x\(String(code, radix: 16)) (\(Self.resultNames[code] ?? "unknown"))"
        case .unsupportedType(let key, let type):
            "\(key): unsupported data type '\(type)'"
        case .unencodable(let key, let number, let type):
            "\(key): \(number) cannot be encoded as '\(type)'"
        }
    }

    private static func prefix(_ key: SMCKey?) -> String {
        key.map { "\($0): " } ?? ""
    }

    private static func describe(_ code: kern_return_t) -> String {
        "IOKit error 0x\(String(UInt32(bitPattern: code), radix: 16)) (\(String(cString: mach_error_string(code))))"
    }

    /// Result codes as named in Acidanthera's VirtualSMC SDK.
    private static let resultNames: [UInt8: String] = [
        0x01: "error",
        0x80: "communication collision",
        0x81: "spurious data",
        0x82: "bad command",
        0x83: "bad parameter",
        0x84: "key not found",
        0x85: "key not readable",
        0x86: "key not writable",
        0x87: "key size mismatch",
        0x88: "framing error",
        0x89: "bad argument",
        0xB7: "timeout",
        0xB8: "key index out of range",
        0xC0: "bad function parameter",
        0xC7: "device access error",
        0xCB: "unsupported feature",
        0xCC: "SMBus access error",
        0xCE: "invalid size",
    ]
}
