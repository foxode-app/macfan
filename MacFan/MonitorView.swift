import AppKit
import MacFanKit
import SwiftUI

/// The monitor window: how much memory is in use, and which of the user's apps and processes use it, each of which can
/// be quit from here.
struct MonitorView: View {
    static let windowID = "monitor"

    @State private var monitor = MemoryMonitor()
    @State private var rowToQuit: MemoryRow?

    var body: some View {
        VStack(spacing: 0) {
            if let usage = monitor.usage {
                MemorySummary(usage: usage, swap: monitor.swap, pressure: monitor.pressure)
                    .padding()
            }
            Divider()
            Table(monitor.rows, children: \.children) {
                TableColumn("Name") { row in
                    nameCell(row)
                }
                TableColumn("Memory") { row in
                    memoryCell(row)
                }
                .width(min: 130, ideal: 150, max: 220)
                TableColumn(Text(verbatim: "")) { row in
                    quitButton(row)
                }
                .width(20)
            }
            Divider()
            footer
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 520, minHeight: 480)
        .task { await monitor.run() }
        .confirmationDialog(
            Text("Quit “\(rowToQuit?.name ?? "")”?"), isPresented: isAskingToQuit, titleVisibility: .visible,
            presenting: rowToQuit
        ) { row in
            Button("Quit") {
                Task { await monitor.quit(row, force: false) }
            }
            Button("Force Quit", role: .destructive) {
                Task { await monitor.quit(row, force: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Force Quit ends it at once, and unsaved changes are lost.")
        }
    }

    private func nameCell(_ row: MemoryRow) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: row.icon)
                .resizable()
                .frame(width: 16, height: 16)
            Group {
                if row.id == .others {
                    Text("Other Processes")
                } else {
                    Text(verbatim: row.name)
                }
            }
            .layoutPriority(1)
            Group {
                if let summary = row.summary {
                    Text(verbatim: summary)
                } else if row.processes.count > 1 {
                    Text("\(row.processes.count) processes")
                }
            }
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .help(row.help)
    }

    /// The size, after a bar that compares it with the largest app or process.
    private func memoryCell(_ row: MemoryRow) -> some View {
        let largest = monitor.rows.first?.footprintBytes ?? 0
        let share = largest > 0 ? min(Double(row.footprintBytes) / Double(largest), 1) : 0
        return HStack(spacing: 8) {
            Capsule()
                .fill(Color(nsColor: MemorySummary.appMemoryColor))
                .frame(width: max(2, 60 * share), height: 6)
                .frame(width: 60, alignment: .leading)
            Text(verbatim: Format.bytes(row.footprintBytes))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func quitButton(_ row: MemoryRow) -> some View {
        if row.canQuit {
            Button {
                rowToQuit = row
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Quit…")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let failure = monitor.quitFailure {
                Text("Couldn’t quit “\(failure.name)”: \(failure.reason)")
                    .foregroundStyle(.red)
            }
            Text(
                """
                Only your own processes are listed. macOS’s own, such as WindowServer, can only be measured as an \
                administrator.
                """
            )
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isAskingToQuit: Binding<Bool> {
        Binding(
            get: { rowToQuit != nil },
            set: { if !$0 { rowToQuit = nil } })
    }
}

/// Memory used and what it is made of, as in Activity Monitor, with how hard macOS is working to find memory.
private struct MemorySummary: View {
    let usage: MemoryUsage
    let swap: SwapUsage?
    let pressure: MemoryPressure?

    /// The first three slots of the dataviz skill's categorical palette, which stay apart for color-blind readers too.
    static let appMemoryColor = NSColor(light: 0x2a78d6, dark: 0x3987e5)
    static let wiredColor = NSColor(light: 0xeb6834, dark: 0xd95926)
    static let compressedColor = NSColor(light: 0x1baf7a, dark: 0x199e70)
    /// Grays, since cached files and free memory are not counted as used.
    static let cachedFilesColor = NSColor(light: 0xaeaeb2, dark: 0x636366)
    static let freeColor = NSColor(light: 0xe5e5ea, dark: 0x2c2c2e)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory Used")
                    .font(.headline)
                Text(verbatim: usedText)
                    .monospacedDigit()
                Spacer()
                if let pressure {
                    PressureLabel(pressure: pressure)
                }
            }
            bar
            HStack(alignment: .top, spacing: 32) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                    legendRow("App Memory", color: Self.appMemoryColor, bytes: usage.appBytes)
                    legendRow("Wired Memory", color: Self.wiredColor, bytes: usage.wiredBytes)
                    legendRow("Compressed", color: Self.compressedColor, bytes: usage.compressedBytes)
                }
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                    legendRow("Cached Files", color: Self.cachedFilesColor, bytes: usage.cachedFilesBytes)
                    if let swap {
                        legendRow("Swap Used", color: nil, bytes: swap.usedBytes)
                    }
                }
            }
            Text(
                """
                Memory Used is app memory, wired memory and compressed memory, as in Activity Monitor. Cached files \
                are freed whenever apps need the room.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var usedText: String {
        "\(Format.percent(usage.fraction))  (\(Format.bytes(usage.usedBytes)) / \(Format.bytes(usage.totalBytes)))"
    }

    /// All of RAM: the used parts, cached files, then free memory, with a gap between parts.
    private var bar: some View {
        let parts: [(UInt64, NSColor)] = [
            (usage.appBytes, Self.appMemoryColor), (usage.wiredBytes, Self.wiredColor),
            (usage.compressedBytes, Self.compressedColor), (usage.cachedFilesBytes, Self.cachedFilesColor),
        ]
        let total = Double(max(usage.totalBytes, 1))
        let free = Color(nsColor: Self.freeColor)
        return Canvas { context, size in
            var x: CGFloat = 0
            for (bytes, color) in parts {
                let width = size.width * min(Double(bytes) / total, 1)
                let part = CGRect(x: x, y: 0, width: max(width - 2, 0), height: size.height)
                context.fill(Path(part), with: .color(Color(nsColor: color)))
                x += width
            }
            let rest = CGRect(x: x, y: 0, width: max(size.width - x, 0), height: size.height)
            context.fill(Path(rest), with: .color(free))
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func legendRow(_ title: LocalizedStringKey, color: NSColor?, bytes: UInt64) -> some View {
        GridRow {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.map { Color(nsColor: $0) } ?? .clear)
                .frame(width: 10, height: 10)
            Text(title)
            Text(verbatim: Format.bytes(bytes))
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}

/// The pressure level in words, after an icon in its status color.
private struct PressureLabel: View {
    let pressure: MemoryPressure

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(Color(nsColor: color))
            Text("Memory Pressure: \(Text(level))")
        }
    }

    private var level: LocalizedStringKey {
        switch pressure {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    private var symbol: String {
        switch pressure {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    /// The dataviz skill's status colors for good, warning and critical, the same in light and dark appearances.
    private var color: NSColor {
        switch pressure {
        case .normal: NSColor(rgb: 0x0ca30c)
        case .warning: NSColor(rgb: 0xfab219)
        case .critical: NSColor(rgb: 0xd03b3b)
        }
    }
}
