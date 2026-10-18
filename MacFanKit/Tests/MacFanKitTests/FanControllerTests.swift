import Testing

@testable import MacFanKit

struct FanControllerTests {
    private func controller(_ smc: FakeSMC) -> FanController {
        FanController(smc: smc, unlockAttempts: 3, retryInterval: 0, sleep: { _ in })
    }

    @Test func readsFanStatus() throws {
        let status = try controller(.appleSiliconMac()).status(ofFan: 0)
        let expected = FanStatus(
            index: 0, actualRPM: 1200, minimumRPM: 1000, maximumRPM: 4900, targetRPM: 1200, mode: .automatic)
        #expect(status == expected)
    }

    @Test func reportsNoFansWhenTheMacHasNone() throws {
        #expect(try controller(FakeSMC()).fanCount() == 0)
    }

    @Test func rejectsFansThatDoNotExist() {
        #expect(throws: FanControlError.noSuchFan(1, fanCount: 1)) {
            try controller(.appleSiliconMac()).status(ofFan: 1)
        }
    }

    @Test func setManualWritesTheModeThenTheTarget() throws {
        let smc = FakeSMC.appleSiliconMac()
        try controller(smc).setManual(fan: 0, rpm: 3000)
        #expect(smc.writtenKeys == ["F0Md", "F0Tg"])
        #expect(smc.number("F0Md") == 1)
        #expect(smc.number("F0Tg") == 3000)
        #expect(smc.number("Ftst") == 0)
    }

    @Test func usesTheLowercaseModeKeyOnM5Macs() throws {
        let smc = FakeSMC.m5Mac()
        let fans = controller(smc)
        #expect(try fans.status(ofFan: 0).mode == .automatic)

        try fans.setManual(fan: 0, rpm: 3000)
        #expect(smc.writtenKeys == ["F0md", "F0Tg"])
        #expect(smc.number("F0md") == 1)

        try fans.restoreAutomaticControl()
        #expect(smc.number("F0md") == 0)
    }

    @Test(arguments: [999, 4901, .nan] as [Double])
    func setManualRejectsSpeedsOutsideTheFanRange(rpm: Double) {
        let smc = FakeSMC.appleSiliconMac()
        #expect(throws: FanControlError.self) { try controller(smc).setManual(fan: 0, rpm: rpm) }
        #expect(smc.writtenKeys.isEmpty)
    }

    @Test func setManualUnlocksWithFtstWhenTheModeWriteIsRejected() throws {
        let smc = FakeSMC.appleSiliconMac()
        smc.onWrite = { [unowned smc] key, bytes in
            if key == "F0Md", smc.number("Ftst") == 0 { throw SMCError.smc(key, 0x82) }
            return bytes
        }
        try controller(smc).setManual(fan: 0, rpm: 3000)
        #expect(smc.number("Ftst") == 1)
        #expect(smc.number("F0Md") == 1)
        #expect(smc.number("F0Tg") == 3000)
    }

    @Test func setManualGivesUpAndClearsFtstWhenTheFanStaysLocked() {
        let smc = FakeSMC.appleSiliconMac()
        smc.onWrite = { key, bytes in
            if key == "F0Md" { throw SMCError.smc(key, 0x82) }
            return bytes
        }
        #expect(throws: FanControlError.manualModeRejected(fan: 0)) {
            try controller(smc).setManual(fan: 0, rpm: 3000)
        }
        #expect(smc.number("Ftst") == 0)
        #expect(smc.number("F0Tg") == 1200)
    }

    @Test func setManualPutsTheModeBackWhenManualDoesNotStick() {
        let smc = FakeSMC.m5Mac()
        smc.onWrite = { key, bytes in key == "F0md" && bytes == [1] ? [2] : bytes }
        #expect(throws: FanControlError.manualModeRejected(fan: 0)) {
            try controller(smc).setManual(fan: 0, rpm: 3000)
        }
        #expect(smc.number("F0md") == 0)
        #expect(smc.number("F0Tg") == 1200)
    }

    @Test func setManualDoesNotRetryWithoutRoot() {
        let smc = FakeSMC.appleSiliconMac()
        smc.onWrite = { key, _ in throw SMCError.ioKit(key, SMCError.notPrivileged) }
        #expect(throws: SMCError.ioKit("F0Md", SMCError.notPrivileged)) {
            try controller(smc).setManual(fan: 0, rpm: 3000)
        }
        #expect(smc.writtenKeys.isEmpty)
    }

    @Test func setManualRequiresAModeKey() {
        let smc = FakeSMC.appleSiliconMac()
        smc.remove("F0Md")
        #expect(throws: FanControlError.manualModeUnsupported(fan: 0)) {
            try controller(smc).setManual(fan: 0, rpm: 3000)
        }
    }

    @Test func restoreOnlyTouchesFansInManualMode() throws {
        let smc = FakeSMC.appleSiliconMac()
        smc.set("FNum", "ui8 ", 2)
        smc.set("F0Md", "ui8 ", 1)
        smc.set("F1Md", "ui8 ", 3)
        smc.set("Ftst", "ui8 ", 1)
        try controller(smc).restoreAutomaticControl()
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("F1Md") == 3)
        #expect(smc.number("Ftst") == 0)
    }

    @Test func restoreKeepsGoingAfterAFailure() {
        let smc = FakeSMC.appleSiliconMac()
        smc.set("F0Md", "ui8 ", 1)
        smc.set("Ftst", "ui8 ", 1)
        smc.onWrite = { key, bytes in
            if key == "F0Md" { throw SMCError.smc(key, 0x86) }
            return bytes
        }
        #expect(throws: SMCError.smc("F0Md", 0x86)) { try controller(smc).restoreAutomaticControl() }
        #expect(smc.number("Ftst") == 0)
    }
}
