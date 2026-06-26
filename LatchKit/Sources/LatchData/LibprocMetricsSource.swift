import Darwin
import LatchDomain

/// Real `MetricsSource` backed by libproc. CPU time + memory footprint come from
/// `proc_pid_rusage(RUSAGE_INFO_V6)`; the live thread count from
/// `proc_pidinfo(PROC_PIDTASKINFO)`. The wall-clock stamp is a monotonic reading so the
/// caller's CPU% delta is immune to clock changes. C types stay inside this adapter;
/// it returns a pure Domain `VitalsReading`. (SPEC §3.2; PLAN slice 2)
///
/// Verified against the macOS SDK headers (`<sys/resource.h>`, `<sys/proc_info.h>`,
/// `libproc.h`): `rusage_info_v6` exposes `ri_user_time`/`ri_system_time` (nanoseconds),
/// `ri_phys_footprint`, `ri_resident_size`; `proc_taskinfo.pti_threadnum` is the live
/// thread count. `RUSAGE_INFO_V6 == 6`. (SPEC §7)
public struct LibprocMetricsSource: MetricsSource {
    public init() {}

    public func sample(pid: Int32) throws -> VitalsReading {
        let usage = try rusage(of: pid)
        return VitalsReading(
            cpuTimeNanos: usage.ri_user_time + usage.ri_system_time,
            physFootprintBytes: usage.ri_phys_footprint,
            residentBytes: usage.ri_resident_size,
            threadCount: try threadCount(of: pid),
            wallClockNanos: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        )
    }

    private func rusage(of pid: Int32) throws -> rusage_info_v6 {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: Optional<UnsafeMutableRawPointer>.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        guard result == 0 else { throw MetricsError.unreadable(pid: pid, errno: errno) }
        return info
    }

    private func threadCount(of pid: Int32) throws -> Int {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let read = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard read == size else { throw MetricsError.unreadable(pid: pid, errno: errno) }
        return Int(info.pti_threadnum)
    }
}

/// Why a vitals read failed: the process exited, or is not readable by this user.
public enum MetricsError: Error, Equatable {
    case unreadable(pid: Int32, errno: Int32)
}
