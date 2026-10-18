import SwiftUI

/// Started by `Launcher`.
struct MacFanApp: App {
    @State private var monitor = SystemMonitor()
    @State private var fanControl = FanControl()
    @State private var language = AppLanguage.saved

    var body: some Scene {
        MenuBarExtra {
            StatusPanel(monitor: monitor, fanControl: fanControl)
                .environment(\.locale, language.locale)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor, fanControl: fanControl, language: languageBinding)
                .environment(\.locale, language.locale)
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: {
                language = $0
                $0.save()
            })
    }
}
