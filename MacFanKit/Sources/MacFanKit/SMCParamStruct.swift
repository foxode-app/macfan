/// Swift mirror of the C `SMCParamStruct` that AppleSMC's user client exchanges (80 bytes).
/// The layout must match C exactly; `SMCParamStructTests` pins the offsets.
struct SMCParamStruct {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    /// `IOConnectCallStructMethod` selector used for every SMC request.
    static let handleYPCEvent: UInt32 = 2
    static let success: UInt8 = 0

    /// Request kinds, passed in `data8`.
    enum Command {
        static let readKey: UInt8 = 5
        static let writeKey: UInt8 = 6
        static let keyFromIndex: UInt8 = 8
        static let keyInfo: UInt8 = 9
    }

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    /// C pads `KeyInfo` to 12 bytes; without this, Swift would pack `result` into that tail padding.
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    var data: [UInt8] {
        get { withUnsafeBytes(of: bytes) { Array($0) } }
        set {
            precondition(newValue.count <= MemoryLayout<Bytes>.size, "SMC payloads are at most 32 bytes")
            withUnsafeMutableBytes(of: &bytes) { $0.copyBytes(from: newValue) }
        }
    }
}
