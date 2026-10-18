/// One reading of everything MacFan displays.
public struct SystemSnapshot: Equatable, Sendable {
    public var cpuTemperature: Double?
    public var gpuTemperature: Double?
    /// Speed, range and mode of each fan; empty on fanless Macs.
    public var fans: [FanStatus]
    /// Fraction of CPU time in use (0–1) since the previous sample.
    public var cpuUsage: Double?
    public var memory: MemoryUsage?

    public init(
        cpuTemperature: Double? = nil, gpuTemperature: Double? = nil, fans: [FanStatus] = [],
        cpuUsage: Double? = nil, memory: MemoryUsage? = nil
    ) {
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
        self.fans = fans
        self.cpuUsage = cpuUsage
        self.memory = memory
    }
}

/// Reads sensors and system statistics. The temperature keys are discovered once, at creation.
public actor SystemSampler {
    private let smc: AppleSMC
    private let sensors: TemperatureSensors
    private let fanController: FanController
    private var previousTicks: CPUTicks?

    public init() throws {
        let smc = try AppleSMC()
        self.smc = smc
        sensors = try TemperatureSensors.discover(in: smc)
        fanController = FanController(smc: smc)
        previousTicks = CPUTicks.current()
    }

    public func sample() -> SystemSnapshot {
        let ticks = CPUTicks.current()
        var cpuUsage: Double?
        if let ticks, let previousTicks {
            cpuUsage = ticks.usage(since: previousTicks)
        }
        previousTicks = ticks
        return SystemSnapshot(
            cpuTemperature: sensors.cpuTemperature(from: smc),
            gpuTemperature: sensors.gpuTemperature(from: smc),
            fans: fanStatuses(),
            cpuUsage: cpuUsage,
            memory: MemoryUsage.current())
    }

    private func fanStatuses() -> [FanStatus] {
        let count = (try? fanController.fanCount()) ?? 0
        return (0..<count).compactMap { try? fanController.status(ofFan: $0) }
    }
}
