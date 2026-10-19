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

/// How the menu bar shows the metrics: as text alone, or in blocks whose background is a meter.
enum MenuBarStyle: String {
    case text
    case meters

    static let storageKey = "menuBarStyle"
    static let `default` = MenuBarStyle.meters
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

    /// Compact menu bar text for each metric, such as `45°C`, `1000 rpm` and `CPU 12%`, with its meter.
    func segments(for snapshot: SystemSnapshot) -> [MenuBarSegment] {
        let widestTemperature = Format.temperature(100)
        let widestPercent = Format.percent(1)
        return items.map { item in
            switch item {
            case .cpuTemperature:
                // A bare temperature is the CPU's, unless the GPU's is shown too.
                MenuBarSegment(
                    label: contains(.gpuTemperature) ? "CPU " : "", value: Format.temperature(snapshot.cpuTemperature),
                    widestValue: widestTemperature, meter: Self.temperatureMeter(snapshot.cpuTemperature))
            case .gpuTemperature:
                MenuBarSegment(
                    label: "GPU ", value: Format.temperature(snapshot.gpuTemperature), widestValue: widestTemperature,
                    meter: Self.temperatureMeter(snapshot.gpuTemperature))
            case .fanSpeed:
                MenuBarSegment(
                    label: "", value: Format.rpm(snapshot.fans.map(\.actualRPM).max()), widestValue: Format.rpm(9999),
                    meter: snapshot.fans.filter { $0.maximumRPM > 0 }.map { $0.actualRPM / $0.maximumRPM }.max())
            case .cpuUsage:
                MenuBarSegment(
                    label: "CPU ", value: Format.percent(snapshot.cpuUsage), widestValue: widestPercent,
                    meter: snapshot.cpuUsage)
            case .memoryUsage:
                MenuBarSegment(
                    label: "MEM ", value: Format.percent(snapshot.memory?.fraction), widestValue: widestPercent,
                    meter: snapshot.memory?.fraction)
            }
        }
    }

    /// A temperature fills its meter at 100 °C.
    private static func temperatureMeter(_ celsius: Double?) -> Double? {
        celsius.map { $0 / 100 }
    }
}

/// One metric's block in the menu bar. The menu bar keeps room for `widestText`, so a reading that gains or loses a
/// digit does not move the other metrics.
struct MenuBarSegment {
    let text: String
    let widestText: String
    /// How much of the metric's limit is in use, from 0 to 1: the share of CPU time or memory, the busiest fan's share
    /// of its maximum speed, or the temperature's share of 100 °C. `nil` without a reading.
    let meter: Double?

    /// `widestValue` has the most digits the value is expected to have. Digits are drawn equally wide, so every value
    /// with that many digits takes the same room.
    init(label: String, value: String, widestValue: String, meter: Double?) {
        text = label + value
        widestText = label + widestValue
        self.meter = meter.map { min(max($0, 0), 1) }
    }
}
