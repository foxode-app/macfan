/// Groups the SMC's temperature keys into CPU and GPU sensors.
///
/// Key names vary between chip generations. Under a CPU-only load on an M5 Pro, the `Tp…` keys rose the most,
/// and the `Tg…` keys belong to the GPU. Earlier Apple silicon also uses `Te…` for its efficiency cores.
public struct TemperatureSensors: Equatable, Sendable {
    public let cpuKeys: [SMCKey]
    public let gpuKeys: [SMCKey]

    public init(keys: [SMCKey]) {
        cpuKeys = keys.filter { Self.hasPrefix($0, ["Tp", "Te"]) }
        gpuKeys = keys.filter { Self.hasPrefix($0, ["Tg"]) }
    }

    /// Finds the temperature keys that currently hold a plausible value.
    public static func discover(in smc: AppleSMC) throws -> TemperatureSensors {
        try TemperatureSensors(keys: smc.temperatures().map(\.key))
    }

    /// Average of the CPU sensors in °C, or `nil` if none can be read.
    public func cpuTemperature(from smc: some SMCDevice) -> Double? {
        Self.average(of: cpuKeys, from: smc)
    }

    /// Average of the GPU sensors in °C, or `nil` if none can be read.
    public func gpuTemperature(from smc: some SMCDevice) -> Double? {
        Self.average(of: gpuKeys, from: smc)
    }

    /// The temperature fan control follows. For `.hottest`, a group that cannot be read is left out, so the result
    /// is `nil` only when neither can be read.
    public func temperature(of sensor: FanControlConfiguration.Sensor, from smc: some SMCDevice) -> Double? {
        switch sensor {
        case .hottest: [cpuTemperature(from: smc), gpuTemperature(from: smc)].compactMap { $0 }.max()
        case .cpu: cpuTemperature(from: smc)
        case .gpu: gpuTemperature(from: smc)
        }
    }

    private static func hasPrefix(_ key: SMCKey, _ prefixes: [String]) -> Bool {
        prefixes.contains { key.description.hasPrefix($0) }
    }

    private static func average(of keys: [SMCKey], from smc: some SMCDevice) -> Double? {
        let values = keys.compactMap { try? smc.readNumber($0) }.filter(isPlausibleTemperature)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// Filters out unpopulated sensors (0) and keys that hold something other than a temperature.
func isPlausibleTemperature(_ celsius: Double) -> Bool {
    celsius > 0 && celsius < 150
}
