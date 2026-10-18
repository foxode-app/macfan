import Foundation

/// The allowed range of the app's refresh interval, and the logarithmic scale of its slider.
public enum RefreshInterval {
    public static let range: ClosedRange<TimeInterval> = 1...300
    public static let defaultValue: TimeInterval = 2

    /// Clamps to `range` and rounds to whole milliseconds. Non-finite input gives the default.
    public static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return defaultValue }
        return (min(max(seconds, range.lowerBound), range.upperBound) * 1000).rounded() / 1000
    }

    /// Slider position (0–1) of an interval. The scale is logarithmic, so 1–10 s get as much of the slider as
    /// 30 s–5 min.
    public static func sliderPosition(for seconds: TimeInterval) -> Double {
        log(clamped(seconds) / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }

    /// The interval at a slider position, rounded to a step that suits its size: 0.1 s below 10 s, 1 s below a
    /// minute and 5 s above.
    public static func interval(atSliderPosition position: Double) -> TimeInterval {
        let raw = range.lowerBound * pow(range.upperBound / range.lowerBound, min(max(position, 0), 1))
        let step: TimeInterval = raw < 10 ? 0.1 : raw < 60 ? 1 : 5
        return clamped((raw / step).rounded() * step)
    }
}
