import AppKit
import MacFanKit
import Observation
import UniformTypeIdentifiers

/// One row of the monitor: an app with all its processes, a process outside any app, or the rest of the processes.
struct MemoryRow: Identifiable {
    enum ID: Hashable {
        case app(path: String)
        case process(ProcessMemory.ID)
        case others
    }

    let id: ID
    let name: String
    /// What a process runs; `nil` for an app.
    let summary: String?
    let icon: NSImage
    let footprintBytes: UInt64
    /// An app's processes, when it has more than one.
    let children: [MemoryRow]?
    /// The app to ask to quit, if the row is an app that is running and takes Quit commands.
    let app: NSRunningApplication?
    /// Every process the row stands for.
    let processes: [ProcessMemory]
    /// The app's path, or the process's command line.
    let help: String

    /// MacFan quits from its own menu, and the rest of the processes are too many to quit at once.
    var canQuit: Bool {
        id != .others && !processes.contains { $0.pid == ProcessInfo.processInfo.processIdentifier }
    }
}

/// Why a quit failed, kept apart so the window can word it in its own language.
struct QuitFailure {
    let name: String
    let reason: String
}

/// Reads the memory in use and the user's processes behind it, every few seconds while the monitor window is open.
@MainActor
@Observable
final class MemoryMonitor {
    /// The apps and processes listed one by one; the rest share a row. A table of over 200 rows makes SwiftUI trip an
    /// AppKit check on macOS 27, and the rest use only a few megabytes each.
    private static let listedRows = 100

    private(set) var usage: MemoryUsage?
    private(set) var swap: SwapUsage?
    private(set) var pressure: MemoryPressure?
    /// The user's apps and processes, using the most memory first, then the rest of them.
    private(set) var rows: [MemoryRow] = []
    private(set) var quitFailure: QuitFailure?

    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var appNames: [String: String] = [:]

    /// Reads the memory at once, so the window opens with its summary in place; the processes follow.
    init() {
        readMemory()
    }

    /// Refreshes until the task is cancelled, which happens when the window closes.
    func run() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Asks an app to quit as its Quit command would, and ends other processes with `SIGTERM`. Force quitting ends
    /// every process of the row with `SIGKILL`.
    func quit(_ row: MemoryRow, force: Bool) async {
        quitFailure = nil
        if force || row.app?.terminate() != true {
            do {
                for process in row.processes {
                    try process.send(force ? SIGKILL : SIGTERM)
                }
            } catch {
                quitFailure = QuitFailure(name: row.name, reason: error.localizedDescription)
            }
        }
        // Gives processes a moment to exit before they are listed again.
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    private func refresh() async {
        let processes = await Task.detached(priority: .utility) { ProcessMemory.all() }.value
        readMemory()
        rows = makeRows(processes)
    }

    private func readMemory() {
        usage = MemoryUsage.current()
        swap = SwapUsage.current()
        pressure = MemoryPressure.current()
    }

    /// Groups processes by app. A process inside several apps counts as the innermost one running as a regular app,
    /// such as Simulator inside Xcode, and otherwise as the outermost, which also takes in helper apps.
    private func makeRows(_ processes: [ProcessMemory]) -> [MemoryRow] {
        var runningApps: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let path = app.bundleURL.flatMap(Self.resolvedPath) else { continue }
            if runningApps[path]?.activationPolicy != .regular {
                runningApps[path] = app
            }
        }
        let groups = Dictionary(grouping: processes) { process in
            let bundles = process.appBundlePaths
            return bundles.last { runningApps[$0]?.activationPolicy == .regular } ?? bundles.first
        }
        var rows = groups[nil, default: []].map(processRow)
        for case (let path?, let members) in groups {
            let app = runningApps[path]
            rows.append(
                MemoryRow(
                    id: .app(path: path), name: app?.localizedName ?? appName(at: path), summary: nil,
                    icon: app?.icon ?? icon(forApp: path), footprintBytes: members.map(\.footprintBytes).reduce(0, +),
                    children: members.count > 1 ? Self.sorted(members.map(processRow)) : nil,
                    app: app?.activationPolicy == .prohibited ? nil : app, processes: members, help: path))
        }
        rows = Self.sorted(rows)
        guard rows.count > Self.listedRows else { return rows }
        let rest = rows[Self.listedRows...].flatMap(\.processes)
        let others = MemoryRow(
            id: .others, name: "", summary: nil, icon: NSWorkspace.shared.icon(for: .unixExecutable),
            footprintBytes: rest.map(\.footprintBytes).reduce(0, +), children: nil, app: nil, processes: rest, help: "")
        return rows.prefix(Self.listedRows) + [others]
    }

    private func processRow(_ process: ProcessMemory) -> MemoryRow {
        MemoryRow(
            id: .process(process.id), name: process.name, summary: process.summary,
            icon: icon(forApp: process.appBundlePaths.last), footprintBytes: process.footprintBytes,
            children: nil, app: nil, processes: [process],
            help: ([process.path ?? process.name] + process.arguments).joined(separator: " "))
    }

    /// The app's icon, or a plain executable's for a process outside any app. The executable's own file would show
    /// as a document when its name has an extension, as Claude Code's version number does.
    private func icon(forApp path: String?) -> NSImage {
        guard let path else { return NSWorkspace.shared.icon(for: .unixExecutable) }
        if let icon = icons[path] {
            return icon
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    private func appName(at path: String) -> String {
        if let name = appNames[path] {
            return name
        }
        // Finder's display name, without the extension that it shows when set to show all extensions.
        let displayName = FileManager.default.displayName(atPath: path)
        let name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        appNames[path] = name
        return name
    }

    private static func sorted(_ rows: [MemoryRow]) -> [MemoryRow] {
        rows.sorted { $0.footprintBytes > $1.footprintBytes }
    }

    /// The path with symbolic links resolved, as the paths of processes' executables have them.
    private static func resolvedPath(_ url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let resolved = realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}
