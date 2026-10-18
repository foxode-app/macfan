import MacFanKit
import SwiftUI

/// A metric that can be shown in the menu bar.
enum MenuBarItem: String, CaseIterable, Identifiable {
    case cpuTemperature
    case gpuTemperature
    case fanSpeed
    case cpuUsage
    case memoryUsage

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .cpuTemperature: "CPU Temperature"
        case .gpuTemperature: "GPU Temperature"
        case .fanSpeed: "Fan Speed"
        case .cpuUsage: "CPU Usage"
        case .memoryUsage: "Memory Usage"
        }
    }
}

/// The metrics shown in the menu bar, kept in `MenuBarItem.allCases` order. Stored in user defaults as a
/// comma-separated list so that `@AppStorage` can hold it.
struct MenuBarItems: RawRepresentable, Equatable {
    static let storageKey = "menuBarItems"
    static let `default` = MenuBarItems([.cpuTemperature])

    private(set) var items: [MenuBarItem]

    init(_ items: some Sequence<MenuBarItem>) {
        let selected = Set(items)
        self.items = MenuBarItem.allCases.filter(selected.contains)
    }

    init?(rawValue: String) {
        self.init(rawValue.split(separator: ",").compactMap { MenuBarItem(rawValue: String($0)) })
    }

    var rawValue: String {
        items.map(\.rawValue).joined(separator: ",")
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    func contains(_ item: MenuBarItem) -> Bool {
        items.contains(item)
    }

    mutating func set(_ item: MenuBarItem, shown: Bool) {
        var selected = Set(items)
        if shown {
            selected.insert(item)
        } else {
            selected.remove(item)
        }
        self = MenuBarItems(selected)
    }

    /// Compact menu bar text, such as `45°C  1000 rpm  CPU 12%`.
    func text(for snapshot: SystemSnapshot) -> String {
        items.map { item in
            switch item {
            case .cpuTemperature:
                // A bare temperature is the CPU's, unless the GPU's is shown too.
                (contains(.gpuTemperature) ? "CPU " : "") + Format.temperature(snapshot.cpuTemperature)
            case .gpuTemperature:
                "GPU " + Format.temperature(snapshot.gpuTemperature)
            case .fanSpeed:
                Format.rpm(snapshot.fans.map(\.actualRPM).max())
            case .cpuUsage:
                "CPU " + Format.percent(snapshot.cpuUsage)
            case .memoryUsage:
                "MEM " + Format.percent(snapshot.memory?.fraction)
            }
        }
        .joined(separator: "  ")
    }
}
