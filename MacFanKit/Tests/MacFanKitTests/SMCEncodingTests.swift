import Testing

@testable import MacFanKit

struct SMCParamStructTests {
    @Test func matchesTheCLayoutAppleSMCExpects() {
        typealias Layout = MemoryLayout<SMCParamStruct>
        #expect(Layout.size == 80)
        #expect(Layout.offset(of: \.keyInfo) == 28)
        #expect(Layout.offset(of: \.result) == 40)
        #expect(Layout.offset(of: \.data8) == 42)
        #expect(Layout.offset(of: \.data32) == 44)
        #expect(Layout.offset(of: \.bytes) == 48)
    }

    @Test func storesPayloadBytesAtTheStart() {
        var param = SMCParamStruct()
        param.data = [1, 2, 3]
        #expect(param.data.prefix(4) == [1, 2, 3, 0])
    }
}

struct SMCKeyTests {
    @Test func convertsToAndFromItsFourCharacterCode() {
        let key: SMCKey = "F0Ac"
        #expect(key.code == 0x4630_4163)
        #expect(key.description == "F0Ac")
        #expect(SMCKey(code: 0x4630_4163) == key)
    }

    @Test(arguments: ["", "F0A", "F0Acc", "Fé0"])
    func rejectsStringsThatAreNotFourASCIICharacters(_ text: String) {
        #expect(SMCKey(text) == nil)
    }
}

struct SMCCodecTests {
    @Test(
        arguments: [
            ("flt ", [0x00, 0x40, 0x9C, 0x44], 1250),
            ("fpe2", [0x13, 0x88], 1250),
            ("sp78", [0x2D, 0x80], 45.5),
            ("sp78", [0xFF, 0x80], -0.5),
            ("ui8 ", [0x01], 1),
            ("ui16", [0x01, 0x02], 258),
            ("ui32", [0x00, 0x00, 0x0A, 0x5A], 2650),
            ("si16", [0xFF, 0xFE], -2),
        ] as [(String, [UInt8], Double)])
    func decodes(type: String, bytes: [UInt8], expected: Double) {
        #expect(SMCCodec.decode(bytes, type: type) == expected)
    }

    @Test func decodingRejectsUnknownTypesAndWrongSizes() {
        #expect(SMCCodec.decode([0x41, 0x42, 0x43, 0x44], type: "ch8*") == nil)
        #expect(SMCCodec.decode([0x00, 0x40], type: "flt ") == nil)
        #expect(SMCCodec.decode([0x00, 0x40], type: "fpzz") == nil)
    }

    @Test func encodesIntoTheKeysOwnType() {
        #expect(SMCCodec.encode(1250, type: "flt ", size: 4) == [0x00, 0x40, 0x9C, 0x44])
        #expect(SMCCodec.encode(1250, type: "fpe2", size: 2) == [0x13, 0x88])
        #expect(SMCCodec.encode(1, type: "ui8 ", size: 1) == [0x01])
    }

    @Test(
        arguments: [
            (256, "ui8 ", 1),
            (-1, "ui8 ", 1),
            (1.5, "ui8 ", 1),
            (.nan, "flt ", 4),
            (16384, "fpe2", 2),
            (1250, "flt ", 2),
            (1, "ch8*", 4),
        ] as [(Double, String, Int)])
    func encodingRejectsValuesThatDoNotFit(number: Double, type: String, size: Int) {
        #expect(SMCCodec.encode(number, type: type, size: size) == nil)
    }
}
