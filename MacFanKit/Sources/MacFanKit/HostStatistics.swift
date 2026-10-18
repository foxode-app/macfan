import Darwin
import Foundation

/// The host port, fetched once: every `mach_host_self()` call adds a port reference.
private let hostPort = mach_host_self()

/// Cumulative CPU time across all cores, in scheduler ticks.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public static func current() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
    }

    /// Fraction of time (0–1) the CPUs were busy since `earlier`, or `nil` if no time has passed.
    /// The kernel's counters are 32-bit and wrap around, so the differences use wrapping arithmetic.
    public func usage(since earlier: CPUTicks) -> Double? {
        let busy = UInt64(user &- earlier.user) + UInt64(system &- earlier.system) + UInt64(nice &- earlier.nice)
        let total = busy + UInt64(idle &- earlier.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }
}

/// Memory in use, counted like Activity Monitor's "Memory Used": app memory, wired and compressed.
public struct MemoryUsage: Equatable, Sendable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public var fraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    public static func current() -> MemoryUsage? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(hostPort, &pageSize) == KERN_SUCCESS else { return nil }
        return MemoryUsage(
            statistics: statistics, pageSize: UInt64(pageSize), totalBytes: ProcessInfo.processInfo.physicalMemory)
    }

    init(statistics: vm_statistics64, pageSize: UInt64, totalBytes: UInt64) {
        let internalPages = UInt64(statistics.internal_page_count)
        let purgeablePages = UInt64(statistics.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let pages = appPages + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
        usedBytes = pages * pageSize
        self.totalBytes = totalBytes
    }
}
