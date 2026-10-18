import Foundation

/// Number formatting shared by the menu bar text and the panel. Missing readings show as a dash.
enum Format {
    static func temperature(_ celsius: Double?, fractionDigits: Int = 0) -> String {
        guard let celsius else { return "—°C" }
        return String(format: "%.\(fractionDigits)f°C", celsius)
    }

    static func rpm(_ rpm: Double?) -> String {
        guard let rpm else { return "— rpm" }
        return String(format: "%.0f rpm", rpm)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—%" }
        return String(format: "%.0f%%", fraction * 100)
    }

    /// A refresh interval: seconds below a minute ("1.5 sec"), minutes and seconds above ("2 min, 30 sec").
    static func interval(_ seconds: TimeInterval, locale: Locale) -> String {
        if seconds < 60 {
            return Measurement(value: seconds, unit: UnitDuration.seconds).formatted(
                .measurement(
                    width: .abbreviated, usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(0...3))
                )
                .locale(locale))
        }
        return Duration.milliseconds(Int64((seconds * 1000).rounded()))
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated).locale(locale))
    }

    static func bytes(_ count: UInt64) -> String {
        Int64(clamping: count).formatted(.byteCount(style: .memory))
    }
}
