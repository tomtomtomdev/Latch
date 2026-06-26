// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// One raw, point-in-time reading of a process's vitals as the OS reports them. CPU
/// time is *cumulative* since process start, so it is meaningless alone — a CPU% is
/// derived from the delta between two readings (see `MetricSample.derive`). The raw
/// counters live in Domain (as a pure value type, not a C struct) so that derivation
/// stays testable. The Data adapter that fills this from libproc owns the C interop.
/// (SPEC §3.2, §4; PLAN slice 2)
public struct VitalsReading: Sendable, Equatable {
    /// Cumulative user + system CPU time since process start, in nanoseconds.
    public let cpuTimeNanos: UInt64
    /// `ri_phys_footprint` — the memory figure that matches the Xcode gauge.
    public let physFootprintBytes: UInt64
    public let residentBytes: UInt64
    public let threadCount: Int
    /// Monotonic clock value captured at read time, in nanoseconds. Used only for the
    /// wall-clock delta between two readings, so its epoch is irrelevant.
    public let wallClockNanos: UInt64

    public init(
        cpuTimeNanos: UInt64,
        physFootprintBytes: UInt64,
        residentBytes: UInt64,
        threadCount: Int,
        wallClockNanos: UInt64
    ) {
        self.cpuTimeNanos = cpuTimeNanos
        self.physFootprintBytes = physFootprintBytes
        self.residentBytes = residentBytes
        self.threadCount = threadCount
        self.wallClockNanos = wallClockNanos
    }
}
