import Testing

@testable import MacFanKit

struct RefreshIntervalTests {
    @Test(arguments: [(0.5, 1), (301, 300), (1.2346, 1.235), (.nan, 2), (.infinity, 2)] as [(Double, Double)])
    func clampsToTheRangeAndWholeMilliseconds(seconds: Double, expected: Double) {
        #expect(RefreshInterval.clamped(seconds) == expected)
    }

    @Test func sliderEndsAreTheRangeBounds() {
        #expect(RefreshInterval.sliderPosition(for: 1) == 0)
        #expect(RefreshInterval.sliderPosition(for: 300) == 1)
        #expect(RefreshInterval.interval(atSliderPosition: 0) == 1)
        #expect(RefreshInterval.interval(atSliderPosition: 1) == 300)
        #expect(RefreshInterval.interval(atSliderPosition: -0.5) == 1)
        #expect(RefreshInterval.interval(atSliderPosition: 1.5) == 300)
    }

    @Test(arguments: [1, 1.5, 2, 9.9, 10, 33, 59, 60, 65, 150, 300] as [Double])
    func sliderRoundTripsValuesOnItsSteps(seconds: Double) {
        #expect(RefreshInterval.interval(atSliderPosition: RefreshInterval.sliderPosition(for: seconds)) == seconds)
    }

    @Test(arguments: [(1.234, 1.2), (33.4, 33), (123, 125)] as [(Double, Double)])
    func sliderSnapsToStepsThatSuitTheInterval(seconds: Double, snapped: Double) {
        #expect(RefreshInterval.interval(atSliderPosition: RefreshInterval.sliderPosition(for: seconds)) == snapped)
    }
}
