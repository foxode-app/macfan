import Foundation
import MacFanKit
import ServiceManagement

/// The entry point. `MacFan --unregister` removes the fan helper and the login item before the app is moved or
/// deleted; otherwise the menu bar app starts.
@main
enum Launcher {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--unregister") {
            exit(unregisterServices() ? 0 : 1)
        }
        MacFanApp.main()
    }

    /// Returns whether everything that was registered could be removed.
    private static func unregisterServices() -> Bool {
        let services = [
            ("fan helper", SMAppService.daemon(plistName: FanHelper.daemonPlistName)),
            ("login item", SMAppService.mainApp),
        ]
        var succeeded = true
        for (name, service) in services {
            guard service.status == .enabled || service.status == .requiresApproval else {
                print("\(name): not registered")
                continue
            }
            do {
                try service.unregister()
                print("\(name): unregistered")
            } catch {
                print("\(name): \(error.localizedDescription)")
                succeeded = false
            }
        }
        return succeeded
    }
}
