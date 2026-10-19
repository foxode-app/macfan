import AppKit
import MacFanKit
import SwiftUI

/// The panel that opens from the menu bar item.
struct StatusPanel: View {
    let monitor: SystemMonitor
    let fanControl: FanControl
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = monitor.errorMessage {
                Text("Sensors unavailable: \(errorMessage)")
                    .foregroundStyle(.red)
            }
            if let errorMessage = fanControl.errorMessage {
                Text("Fan control error: \(errorMessage)")
                    .foregroundStyle(.red)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("CPU Temperature", Format.temperature(snapshot.cpuTemperature, fractionDigits: 1))
                row("GPU Temperature", Format.temperature(snapshot.gpuTemperature, fractionDigits: 1))
                ForEach(snapshot.fans, id: \.index) { fan in
                    row("Fan \(fan.index + 1)") {
                        HStack(spacing: 4) {
                            Text(verbatim: Format.rpm(fan.actualRPM))
                            if let mode = modeLabel(fan.mode) {
                                Text(verbatim: "·")
                                Text(mode)
                            }
                        }
                    }
                }
                row("CPU Usage", Format.percent(snapshot.cpuUsage))
                row("Memory Usage", memoryText)
            }
            Divider()
            HStack {
                Button("Settings…") {
                    openSettings()
                    NSApp.activate()
                }
                Spacer()
                Button("Monitor…") {
                    openWindow(id: MonitorView.windowID)
                    NSApp.activate()
                }
                Spacer()
                Button("Quit MacFan") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var snapshot: SystemSnapshot {
        monitor.snapshot
    }

    /// Who controls the fan, shown after its speed.
    private func modeLabel(_ mode: FanMode?) -> LocalizedStringKey? {
        switch mode {
        case .automatic: "Auto"
        case .manual: "Manual"
        case .other, nil: nil
        }
    }

    private var memoryText: String {
        guard let memory = snapshot.memory else { return Format.percent(nil) }
        let used = Format.bytes(memory.usedBytes)
        let total = Format.bytes(memory.totalBytes)
        return "\(Format.percent(memory.fraction))  (\(used) / \(total))"
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        row(title) { Text(verbatim: value) }
    }

    private func row<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            value()
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
    }
}
