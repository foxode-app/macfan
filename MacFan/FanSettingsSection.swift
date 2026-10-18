import MacFanKit
import SwiftUI

/// Settings for how MacFan drives the fans: left to macOS, a constant speed, or a speed that follows a temperature.
struct FanSettingsSection: View {
    @Bindable var fanControl: FanControl
    /// The first fan, for showing percentages as rpm.
    let fan: FanStatus?

    private var configuration: FanControlConfiguration {
        fanControl.configuration
    }

    var body: some View {
        Section {
            Picker("Fan Control", selection: $fanControl.configuration.mode) {
                Text("Automatic (System)").tag(FanControlConfiguration.Mode.automatic)
                Text("Custom").tag(FanControlConfiguration.Mode.custom)
            }
            .pickerStyle(.radioGroup)

            if configuration.mode == .custom {
                Picker("Method", selection: $fanControl.configuration.customMode) {
                    Text("Constant Speed").tag(FanControlConfiguration.CustomMode.constantSpeed)
                    Text("Based on Temperature").tag(FanControlConfiguration.CustomMode.temperature)
                }
                .pickerStyle(.segmented)
                Toggle("Change Speed Gradually", isOn: $fanControl.configuration.changesGradually)

                switch configuration.customMode {
                case .constantSpeed:
                    percentRow("Speed", value: $fanControl.configuration.constantPercent)
                case .temperature:
                    Picker("Sensor", selection: $fanControl.configuration.sensor) {
                        Text("Higher of CPU and GPU (Recommended)").tag(FanControlConfiguration.Sensor.hottest)
                        Text(verbatim: "CPU").tag(FanControlConfiguration.Sensor.cpu)
                        Text(verbatim: "GPU").tag(FanControlConfiguration.Sensor.gpu)
                    }
                    temperatureRow("Start Temperature", value: startTemperature, in: startTemperatureRange)
                    temperatureRow("Maximum Temperature", value: maximumTemperature, in: maximumTemperatureRange)
                    percentRow("Maximum Speed", value: $fanControl.configuration.maximumPercent)
                }
                helperStatus
            }
        } header: {
            Text("Fan")
        } footer: {
            if configuration.mode == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    if configuration.customMode == .temperature {
                        Text(
                            """
                            Below the start temperature, macOS controls the fans. Above it, the speed rises from the \
                            fan's minimum and reaches the maximum speed at the maximum temperature.
                            """)
                        let reference = MacOSFanReference.self
                        Text(
                            """
                            For reference, on an \(reference.model) macOS started raising the fan at about \
                            \(reference.rampStart)°C and, under a sustained full CPU load, held about \
                            \(reference.sustainedTemperature)°C with the fan at \(reference.sustainedRPM) rpm \
                            (\(reference.sustainedPercent)% of its maximum).
                            """)
                    }
                    if configuration.changesGradually {
                        let rate = Int(FanControlConfiguration.rampRate)
                        Text(
                            """
                            Gradual changes move the speed by about \(rate) rpm per second, close to what macOS does.
                            """)
                    }
                    let emergency = Int(FanControlConfiguration.emergencyTemperature)
                    Text("Above \(emergency)°C, the fans always go back to macOS.")
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var helperStatus: some View {
        switch fanControl.helperState {
        case .requiresApproval:
            VStack(alignment: .leading, spacing: 6) {
                Text("To control the fans, allow MacFan in System Settings → General → Login Items & Extensions.")
                Button("Open System Settings") {
                    fanControl.openSystemSettings()
                }
            }
        case .notRegistered, .enabled:
            EmptyView()
        }
        if let errorMessage = fanControl.errorMessage {
            Text("Fan control error: \(errorMessage)")
                .foregroundStyle(.red)
        }
    }

    /// Start and maximum temperatures stay at least a degree apart, whichever one is typed in.
    private var startTemperatureRange: ClosedRange<Double> {
        FanControlConfiguration.temperatureRange.lowerBound...(configuration.maximumTemperature - 1)
    }

    private var maximumTemperatureRange: ClosedRange<Double> {
        (configuration.startTemperature + 1)...FanControlConfiguration.temperatureRange.upperBound
    }

    private var startTemperature: Binding<Double> {
        Binding(
            get: { configuration.startTemperature },
            set: { fanControl.configuration.startTemperature = $0.rounded().clamped(to: startTemperatureRange) })
    }

    private var maximumTemperature: Binding<Double> {
        Binding(
            get: { configuration.maximumTemperature },
            set: { fanControl.configuration.maximumTemperature = $0.rounded().clamped(to: maximumTemperatureRange) })
    }

    private func temperatureRow(
        _ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Stepper(title, value: value, in: range, step: 1)
                    .labelsHidden()
                Text(verbatim: "°C")
            }
        }
    }

    private func percentRow(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        LabeledContent {
            HStack {
                Slider(value: value, in: 0...100, step: 1) {
                    Text(title)
                }
                .labelsHidden()
                Text(verbatim: "\(Int(value.wrappedValue))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        } label: {
            Text(title)
            if let fan {
                let rpm = FanControlConfiguration.rpm(
                    forPercent: value.wrappedValue, minimumRPM: fan.minimumRPM, maximumRPM: fan.maximumRPM)
                Text(verbatim: Format.rpm(rpm))
            }
        }
    }
}

/// macOS's own fan behaviour, measured on an M5 Pro Mac mini (Mac17,16, macOS 27) under eight minutes of full CPU
/// load. Temperatures are on MacFan's scale, the higher of the CPU and GPU averages; other Macs will differ.
private enum MacOSFanReference {
    static let model = "M5 Pro Mac mini"
    static let rampStart = 80
    static let sustainedTemperature = 84
    static let sustainedRPM = 3150
    static let sustainedPercent = 64
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
