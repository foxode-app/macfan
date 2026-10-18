import SwiftUI

/// The menu bar item itself: the selected metrics, or a fan icon when none are selected.
struct MenuBarLabel: View {
    let monitor: SystemMonitor
    @AppStorage(MenuBarItems.storageKey) private var items = MenuBarItems.default

    var body: some View {
        if items.isEmpty {
            Image(systemName: "fan")
        } else {
            Text(items.text(for: monitor.snapshot))
                .monospacedDigit()
        }
    }
}
