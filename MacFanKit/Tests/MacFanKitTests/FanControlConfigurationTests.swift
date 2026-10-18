import Foundation
import Testing

@testable import MacFanKit

struct FanControlConfigurationTests {
    private func target(
        _ configuration: FanControlConfiguration, at temperature: Double?, engaged: Bool = false
    ) -> FanTarget {
        configuration.target(temperature: temperature, minimumRPM: 1000, maximumRPM: 4900, engaged: engaged)
    }

    @Test func defaultsToMacOSControlFollowingTheHotterSensor() {
        let configuration = FanControlConfiguration()
        #expect(configuration.mode == .automatic)
        #expect(configuration.sensor == .hottest)
        #expect(target(configuration, at: 70) == .automatic)
    }

    @Test func constantSpeedIsAShareOfTheMaximumButNeverBelowTheMinimum() {
        var configuration = FanControlConfiguration(mode: .custom, customMode: .constantSpeed, constantPercent: 50)
        #expect(target(configuration, at: 40) == .rpm(2450))
        configuration.constantPercent = 10
        #expect(target(configuration, at: 40) == .rpm(1000))
    }

    @Test func temperatureModeRampsFromTheMinimumAboveTheStartTemperature() {
        let configuration = FanControlConfiguration(mode: .custom, startTemperature: 60, maximumTemperature: 80)
        #expect(target(configuration, at: 60) == .automatic)
        #expect(target(configuration, at: 70) == .rpm(2950))
        #expect(target(configuration, at: 90) == .rpm(4900))
    }

    @Test func maximumPercentCapsTheSpeed() {
        let configuration = FanControlConfiguration(
            mode: .custom, startTemperature: 60, maximumTemperature: 80, maximumPercent: 50)
        #expect(target(configuration, at: 70) == .rpm(1725))
        #expect(target(configuration, at: 85) == .rpm(2450))
    }

    @Test func engagedFansStayEngagedUntilTheHysteresisIsCleared() {
        let configuration = FanControlConfiguration(mode: .custom, startTemperature: 60, maximumTemperature: 80)
        #expect(target(configuration, at: 59, engaged: true) == .rpm(1000))
        #expect(target(configuration, at: 58, engaged: true) == .automatic)
    }

    @Test(arguments: [nil, 95, 120] as [Double?])
    func unreadableOrDangerousTemperaturesHandTheFansBack(temperature: Double?) {
        let configuration = FanControlConfiguration(mode: .custom, customMode: .constantSpeed)
        #expect(target(configuration, at: temperature) == .automatic)
    }

    @Test func gradualChangesMoveAtTheRampRate() {
        let gradual = FanControlConfiguration()
        #expect(gradual.nextRPM(from: 1000, toward: 3000, elapsed: 1) == 1040)
        #expect(gradual.nextRPM(from: 3000, toward: 1000, elapsed: 1) == 2960)
        #expect(gradual.nextRPM(from: 2980, toward: 3000, elapsed: 1) == 3000)

        let immediate = FanControlConfiguration(changesGradually: false)
        #expect(immediate.nextRPM(from: 1000, toward: 3000, elapsed: 1) == 3000)
    }

    @Test func settingsSavedBeforeANewOptionStillLoad() throws {
        let saved = Data(
            #"{"mode":"custom","customMode":"temperature","constantPercent":50,"sensor":"cpu","startTemperature":50,"maximumTemperature":60,"maximumPercent":80}"#
                .utf8)
        let configuration = try JSONDecoder().decode(FanControlConfiguration.self, from: saved)
        #expect(configuration.mode == .custom)
        #expect(configuration.sensor == .cpu)
        #expect(configuration.startTemperature == 50)
        #expect(configuration.maximumPercent == 80)
        #expect(configuration.changesGradually)
    }

    @Test func rejectsInconsistentSettings() {
        #expect(FanControlConfiguration().isValid)
        #expect(!FanControlConfiguration(startTemperature: 80, maximumTemperature: 70).isValid)
        #expect(!FanControlConfiguration(maximumPercent: 120).isValid)
        #expect(!FanControlConfiguration(startTemperature: 20).isValid)
    }
}
