import Darwin
import Testing

@testable import MacFanKit

struct CPUTicksTests {
    @Test func usageIsTheBusyShareOfElapsedTicks() {
        let earlier = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let later = CPUTicks(user: 200, system: 100, idle: 1650, nice: 10)
        #expect(later.usage(since: earlier) == 160.0 / 960.0)
    }

    @Test func usageHandlesCounterWraparound() {
        let earlier = CPUTicks(user: .max - 9, system: 0, idle: .max - 29, nice: 0)
        let later = CPUTicks(user: 10, system: 0, idle: 10, nice: 0)
        #expect(later.usage(since: earlier) == 20.0 / 60.0)
    }

    @Test func usageIsUnknownWhenNoTimeHasPassed() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(ticks.usage(since: ticks) == nil)
    }

    @Test func readsTheCurrentCounters() {
        #expect(CPUTicks.current() != nil)
    }
}

struct MemoryUsageTests {
    @Test func countsAppWiredAndCompressedMemory() {
        var statistics = vm_statistics64()
        statistics.internal_page_count = 1000
        statistics.purgeable_count = 100
        statistics.wire_count = 200
        statistics.compressor_page_count = 50
        statistics.free_count = 5000
        let usage = MemoryUsage(statistics: statistics, pageSize: 16384, totalBytes: 16384 * 4000)
        #expect(usage.usedBytes == 1150 * 16384)
        #expect(usage.fraction == 1150.0 / 4000.0)
    }

    @Test func readsTheCurrentUsage() throws {
        let usage = try #require(MemoryUsage.current())
        #expect(usage.usedBytes > 0)
        #expect(usage.usedBytes <= usage.totalBytes)
    }
}

struct TemperatureSensorsTests {
    @Test func sortsKeysIntoCPUAndGPUByPrefix() {
        let sensors = TemperatureSensors(keys: ["Tp00", "Te05", "Tg0G", "Ta00", "Tm00"])
        #expect(sensors.cpuKeys == ["Tp00", "Te05"])
        #expect(sensors.gpuKeys == ["Tg0G"])
    }

    @Test func averagesReadableSensorsAndSkipsImplausibleValues() {
        let smc = FakeSMC()
        smc.set("Tp00", "flt ", 40)
        smc.set("Tp04", "flt ", 50)
        smc.set("Tp08", "flt ", 0)
        let sensors = TemperatureSensors(keys: ["Tp00", "Tp04", "Tp08", "Tp0C"])
        #expect(sensors.cpuTemperature(from: smc) == 45)
        #expect(sensors.gpuTemperature(from: smc) == nil)
    }

    @Test func hottestFollowsWhicheverGroupIsHotter() {
        let smc = FakeSMC()
        smc.set("Tp00", "flt ", 50)
        smc.set("Tg00", "flt ", 60)
        let sensors = TemperatureSensors(keys: ["Tp00", "Tg00"])
        #expect(sensors.temperature(of: .hottest, from: smc) == 60)
        #expect(sensors.temperature(of: .cpu, from: smc) == 50)
        #expect(sensors.temperature(of: .gpu, from: smc) == 60)
    }

    @Test func hottestFallsBackToTheGroupThatCanBeRead() {
        let smc = FakeSMC()
        smc.set("Tp00", "flt ", 50)
        #expect(TemperatureSensors(keys: ["Tp00", "Tg00"]).temperature(of: .hottest, from: smc) == 50)
        #expect(TemperatureSensors(keys: []).temperature(of: .hottest, from: smc) == nil)
    }
}
