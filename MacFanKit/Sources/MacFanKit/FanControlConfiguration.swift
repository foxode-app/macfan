/// How MacFan drives the fans. The app edits and stores it; the privileged helper applies it.
public struct FanControlConfiguration: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// macOS controls the fans.
        case automatic
        /// MacFan controls the fans as `customMode` describes.
        case custom
    }

    public enum CustomMode: String, Codable, Sendable {
        /// A fixed speed: `constantPercent` of the fan's maximum.
        case constantSpeed
        /// macOS keeps control until `sensor` passes `startTemperature`. Above it, MacFan raises the speed
        /// linearly from the fan's minimum to `maximumPercent` of its maximum, reached at `maximumTemperature`.
        case temperature
    }

    public enum Sensor: String, Codable, Sendable {
        /// The higher of the CPU and GPU temperatures. The two share one chip and one cooler, but whichever part
        /// is working hard runs hotter, so following the higher one answers both kinds of load.
        case hottest
        case cpu
        case gpu
    }

    /// Temperatures the settings may use, in °C.
    public static let temperatureRange: ClosedRange<Double> = 30...100
    /// Above this the fans go back to macOS, whatever the settings say.
    public static let emergencyTemperature: Double = 95
    /// How far below `startTemperature` the sensor must fall before engaged fans go back to macOS, so that
    /// they do not flip between macOS and MacFan right at the threshold.
    public static let hysteresis: Double = 2
    /// How fast `changesGradually` moves a fan toward its target, in rpm per second. macOS was measured moving
    /// about 26–34 rpm per second on an M5 Pro Mac mini.
    public static let rampRate: Double = 40

    public var mode: Mode
    public var customMode: CustomMode
    public var constantPercent: Double
    public var sensor: Sensor
    public var startTemperature: Double
    public var maximumTemperature: Double
    public var maximumPercent: Double
    /// Moves the speed toward its target at `rampRate` instead of jumping, as macOS does.
    public var changesGradually: Bool

    public init(
        mode: Mode = .automatic, customMode: CustomMode = .temperature, constantPercent: Double = 50,
        sensor: Sensor = .hottest, startTemperature: Double = 60, maximumTemperature: Double = 85,
        maximumPercent: Double = 100, changesGradually: Bool = true
    ) {
        self.mode = mode
        self.customMode = customMode
        self.constantPercent = constantPercent
        self.sensor = sensor
        self.startTemperature = startTemperature
        self.maximumTemperature = maximumTemperature
        self.maximumPercent = maximumPercent
        self.changesGradually = changesGradually
    }

    /// Settings saved by an older version lack newer keys; those take their defaults instead of failing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FanControlConfiguration()
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? defaults.mode
        customMode = try container.decodeIfPresent(CustomMode.self, forKey: .customMode) ?? defaults.customMode
        constantPercent =
            try container.decodeIfPresent(Double.self, forKey: .constantPercent) ?? defaults.constantPercent
        sensor = try container.decodeIfPresent(Sensor.self, forKey: .sensor) ?? defaults.sensor
        startTemperature =
            try container.decodeIfPresent(Double.self, forKey: .startTemperature) ?? defaults.startTemperature
        maximumTemperature =
            try container.decodeIfPresent(Double.self, forKey: .maximumTemperature) ?? defaults.maximumTemperature
        maximumPercent = try container.decodeIfPresent(Double.self, forKey: .maximumPercent) ?? defaults.maximumPercent
        changesGradually =
            try container.decodeIfPresent(Bool.self, forKey: .changesGradually) ?? defaults.changesGradually
    }

    /// Whether the helper may apply these settings.
    public var isValid: Bool {
        Self.temperatureRange.contains(startTemperature) && Self.temperatureRange.contains(maximumTemperature)
            && startTemperature < maximumTemperature
            && (0...100).contains(constantPercent) && (0...100).contains(maximumPercent)
    }

    /// The speed for `percent` of a fan's maximum, never below its minimum.
    public static func rpm(forPercent percent: Double, minimumRPM: Double, maximumRPM: Double) -> Double {
        min(max(maximumRPM * percent / 100, minimumRPM), maximumRPM)
    }

    /// The speed to write next on the way from `current` to `target`, `elapsed` seconds after the last write.
    public func nextRPM(from current: Double, toward target: Double, elapsed: Double) -> Double {
        guard changesGradually else { return target }
        let maximumStep = Self.rampRate * elapsed
        return current + min(max(target - current, -maximumStep), maximumStep)
    }

    /// What a fan should do at `temperature`. `engaged` says whether MacFan is already holding the fans.
    /// An unreadable sensor, or one past `emergencyTemperature`, always gives the fans back to macOS.
    public func target(temperature: Double?, minimumRPM: Double, maximumRPM: Double, engaged: Bool) -> FanTarget {
        guard mode == .custom, let temperature, temperature < Self.emergencyTemperature else { return .automatic }
        switch customMode {
        case .constantSpeed:
            return .rpm(Self.rpm(forPercent: constantPercent, minimumRPM: minimumRPM, maximumRPM: maximumRPM))
        case .temperature:
            let threshold = engaged ? startTemperature - Self.hysteresis : startTemperature
            guard temperature > threshold else { return .automatic }
            let top = Self.rpm(forPercent: maximumPercent, minimumRPM: minimumRPM, maximumRPM: maximumRPM)
            let progress = min(max((temperature - startTemperature) / (maximumTemperature - startTemperature), 0), 1)
            return .rpm(minimumRPM + (top - minimumRPM) * progress)
        }
    }
}

public enum FanTarget: Equatable, Sendable {
    case automatic
    case rpm(Double)
}
