import AppKit
import MacFanKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var monitor: SystemMonitor
    let fanControl: FanControl
    @Binding var language: AppLanguage
    @Environment(\.locale) private var locale
    @AppStorage(MenuBarItems.storageKey) private var menuBarItems = MenuBarItems.default
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.label).tag(language)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("Window titles and other system text switch after MacFan restarts.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart", action: restart)
                    }
                }
            }

            Section {
                ForEach(MenuBarItem.allCases) { item in
                    Toggle(item.title, isOn: shownBinding(for: item))
                }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("With nothing selected, the menu bar shows a fan icon.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Slider(value: intervalPosition, in: 0...1) {
                        Text("Update Interval")
                    } minimumValueLabel: {
                        Text(Format.interval(RefreshInterval.range.lowerBound, locale: locale))
                    } maximumValueLabel: {
                        Text(Format.interval(RefreshInterval.range.upperBound, locale: locale))
                    }
                    .labelsHidden()
                } label: {
                    Text("Update Interval")
                    Text(Format.interval(monitor.refreshInterval, locale: locale))
                        .monospacedDigit()
                }
                LabeledContent("Seconds") {
                    TextField("Seconds", value: exactInterval, format: .number.precision(.fractionLength(0...3)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            FanSettingsSection(fanControl: fanControl, fan: monitor.snapshot.fans.first)

            Section {
                Toggle("Open at Login", isOn: loginItemBinding)
                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shownBinding(for item: MenuBarItem) -> Binding<Bool> {
        Binding(
            get: { menuBarItems.contains(item) },
            set: { menuBarItems.set(item, shown: $0) })
    }

    /// Logarithmic slider position, snapped to a step that suits the interval's size.
    private var intervalPosition: Binding<Double> {
        Binding(
            get: { RefreshInterval.sliderPosition(for: monitor.refreshInterval) },
            set: { monitor.refreshInterval = RefreshInterval.interval(atSliderPosition: $0) })
    }

    /// Exact entry in seconds, to the millisecond. Values outside the range are clamped.
    private var exactInterval: Binding<TimeInterval> {
        Binding(
            get: { monitor.refreshInterval },
            set: { monitor.refreshInterval = RefreshInterval.clamped($0) })
    }

    /// Registers or unregisters the app as a login item, then reflects what the system actually did.
    /// Starts a fresh copy of the app, which loads the new language everywhere, then quits this one.
    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { opensAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginItemError = nil
                } catch {
                    loginItemError = error.localizedDescription
                }
                opensAtLogin = SMAppService.mainApp.status == .enabled
            })
    }
}
