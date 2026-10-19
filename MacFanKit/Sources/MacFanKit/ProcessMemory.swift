import Darwin
import Foundation

/// A process of the current user and the memory it uses. Other users' processes, such as macOS's own daemons, can only
/// be read as root, so they are left out.
public struct ProcessMemory: Equatable, Sendable, Identifiable {
    /// Tells a process apart from a later one that is given the same process ID.
    public struct ID: Hashable, Sendable {
        public let pid: pid_t
        /// When the process started, in Mach absolute time.
        let startTime: UInt64
    }

    public let id: ID
    /// The name the process was started under, which can differ from its executable's: Claude Code runs as `claude`
    /// from a file named after its version.
    public let name: String
    /// The executable's path, if it could be read.
    public let path: String?
    /// The arguments after the name.
    public let arguments: [String]
    /// The memory the process uses for itself, including what macOS has compressed: Activity Monitor's Memory column.
    public let footprintBytes: UInt64

    public var pid: pid_t { id.pid }

    /// The app bundles the executable is in, outermost first. An app's helpers are apps inside it.
    public var appBundlePaths: [String] {
        path.map(Self.appBundlePaths(containing:)) ?? []
    }

    /// The arguments, for telling processes with the same name apart. For a Java program they start at its main class
    /// or JAR file, shown without its package or folder, since the JVM's options before it would take up all the room.
    public var summary: String {
        Self.summary(name: name, arguments: arguments)
    }

    /// Every process of the current user that is still running, in no particular order.
    public static func all() -> [ProcessMemory] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Leaves room for processes started in the meantime.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let listed = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var commandLines = CommandLineReader()
        return pids.prefix(Int(max(listed, 0))).compactMap { ProcessMemory(pid: $0, commandLines: &commandLines) }
    }

    /// Sends `signal` to the process, unless it has exited. The process ID is checked to still belong to this process
    /// first, so that a process started since under the same ID is left alone.
    public func send(_ signal: Int32) throws {
        guard Self.resourceUsage(of: pid)?.ri_proc_start_abstime == id.startTime else { return }
        guard kill(pid, signal) == 0 || errno == ESRCH else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
        }
    }

    init(id: ID, name: String, path: String?, arguments: [String], footprintBytes: UInt64) {
        self.id = id
        self.name = name
        self.path = path
        self.arguments = arguments
        self.footprintBytes = footprintBytes
    }

    /// Reads a process, or returns nil if it has exited or belongs to another user.
    init?(pid: pid_t, commandLines: inout CommandLineReader) {
        guard let usage = Self.resourceUsage(of: pid), usage.ri_phys_footprint > 0 else { return nil }
        let commandLine = commandLines.read(pid) ?? []
        let startedAs = commandLine.first.map { ($0 as NSString).lastPathComponent } ?? ""
        guard let name = startedAs.isEmpty ? Self.name(of: pid) : startedAs else { return nil }
        self.init(
            id: ID(pid: pid, startTime: usage.ri_proc_start_abstime), name: name, path: Self.executablePath(of: pid),
            arguments: Array(commandLine.dropFirst()), footprintBytes: usage.ri_phys_footprint)
    }

    /// Fails for processes of other users.
    private static func resourceUsage(of pid: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? usage : nil
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
    }

    /// The executable's name, cut to 32 bytes.
    private static func name(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
    }

    static func appBundlePaths(containing path: String) -> [String] {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.indices.dropLast().filter { components[$0].hasSuffix(".app") }.map {
            components[...$0].joined(separator: "/")
        }
    }

    static func summary(name: String, arguments: [String]) -> String {
        let shown = name == "java" ? javaProgram(in: arguments) ?? arguments : arguments
        return shown.joined(separator: " ")
    }

    /// Options of the `java` launcher that take the next argument as their value.
    private static let javaOptionsWithValue: Set = [
        "-cp", "-classpath", "--class-path", "-p", "--module-path", "--upgrade-module-path", "--add-modules",
        "--limit-modules", "--add-reads", "--add-exports", "--add-opens", "--patch-module", "--enable-native-access",
        "--source",
    ]

    /// The arguments from the main class or JAR file on, which is shortened to its name.
    private static func javaProgram(in arguments: [String]) -> [String]? {
        var index = 0
        while index < arguments.count, arguments[index].hasPrefix("-") {
            let option = arguments[index]
            index += 1
            if ["-jar", "-m", "--module"].contains(option) {
                break
            }
            if javaOptionsWithValue.contains(option) {
                index += 1
            }
        }
        guard index < arguments.count else { return nil }
        let main = arguments[index]
        let shortMain =
            main.hasSuffix(".jar") || main.hasSuffix(".java")
            ? (main as NSString).lastPathComponent
            : main.split { $0 == "." || $0 == "/" }.last.map(String.init) ?? main
        return [shortMain] + arguments[(index + 1)...]
    }

    /// Splits what `KERN_PROCARGS2` returns: the number of arguments, the executable's path padded with NULs, then the
    /// arguments, each ending in a NUL. The environment variables after them are not read.
    static func parseCommandLine(_ bytes: ArraySlice<UInt8>) -> [String]? {
        guard bytes.count > MemoryLayout<Int32>.size else { return nil }
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = bytes.startIndex + MemoryLayout<Int32>.size
        index = bytes[index...].firstIndex(of: 0) ?? bytes.endIndex
        index = bytes[index...].firstIndex { $0 != 0 } ?? bytes.endIndex
        var arguments: [String] = []
        while arguments.count < count, index < bytes.endIndex {
            let end = bytes[index...].firstIndex(of: 0) ?? bytes.endIndex
            arguments.append(String(decoding: bytes[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments
    }
}

/// Reads processes' command lines into one buffer, as large as a command line can be.
struct CommandLineReader {
    private var buffer: [UInt8]

    init() {
        var maximum: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.argmax", &maximum, &size, nil, 0)
        buffer = [UInt8](repeating: 0, count: max(Int(maximum), 1 << 16))
    }

    /// The arguments, starting with the name the process was started under, or nil if they cannot be read.
    mutating func read(_ pid: pid_t) -> [String]? {
        var name = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buffer.count
        let result = buffer.withUnsafeMutableBytes { sysctl(&name, u_int(name.count), $0.baseAddress, &size, nil, 0) }
        return result == 0 ? ProcessMemory.parseCommandLine(buffer.prefix(size)) : nil
    }
}
