import Darwin
import Foundation
import MachO

/// Mac uzaktan-dashboard'una (iOS) push edilen CPU/RAM ölçümleri.
///
/// `cpuUsagePercent()` iki `HOST_CPU_LOAD_INFO` snapshot'ı arasındaki tick farkına
/// dayanır; ilk çağrı baseline kaydı için 0.0 döner. Bu yüzden actor — paylaşılan
/// `previousTicks` state'i izole eder. `memoryUsagePercent()` state'siz.
actor SystemStats {
    static let shared = SystemStats()

    private var previousTicks: CPUTicks?

    /// Aggregate CPU kullanım yüzdesi (0–100). İlk çağrı 0; sonrakiler
    /// (user + system + nice) / total * 100.
    func cpuUsagePercent() -> Double {
        guard let current = Self.readCPUTicks() else { return 0 }
        defer { previousTicks = current }
        guard let previous = previousTicks else { return 0 }
        return Self.computePercent(previous: previous, current: current)
    }

    nonisolated static func memoryUsagePercent() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        let used = Double(info.resident_size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(100.0, (used / total) * 100.0)
    }

    // MARK: - Internals

    struct CPUTicks: Equatable, Sendable {
        let user: UInt32
        let system: UInt32
        let idle: UInt32
        let nice: UInt32
    }

    nonisolated static func readCPUTicks() -> CPUTicks? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var load = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: load.cpu_ticks.0,
            system: load.cpu_ticks.1,
            idle: load.cpu_ticks.2,
            nice: load.cpu_ticks.3
        )
    }

    /// `&-` overflow-safe tick farkı; unit-test edilebilir saf hesap.
    nonisolated static func computePercent(previous: CPUTicks, current: CPUTicks) -> Double {
        let userDelta = Double(current.user &- previous.user)
        let systemDelta = Double(current.system &- previous.system)
        let idleDelta = Double(current.idle &- previous.idle)
        let niceDelta = Double(current.nice &- previous.nice)
        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else { return 0 }
        let active = userDelta + systemDelta + niceDelta
        return min(100.0, max(0.0, (active / total) * 100.0))
    }
}
