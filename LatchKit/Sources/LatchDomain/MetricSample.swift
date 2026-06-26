// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// A derived, display-ready vitals sample for one polling tick: CPU% computed from the
/// delta between two raw readings, plus the latest memory and thread figures. This is
/// the entity the dashboard charts and thresholds consume. Network, disk, and energy
/// fields from SPEC §4 arrive in later slices — only the live mem+CPU signals exist
/// here. (SPEC §4; PLAN slice 2)
public struct MetricSample: Sendable, Equatable {
    /// CPU usage as a percentage of **one core**: 100 means one core fully busy, 200
    /// means two. Matches the "% of one core" threshold in SPEC §3.3.
    public let cpuPercent: Double
    public let physFootprintBytes: UInt64
    public let residentBytes: UInt64
    public let threadCount: Int

    public init(cpuPercent: Double, physFootprintBytes: UInt64, residentBytes: UInt64, threadCount: Int) {
        self.cpuPercent = cpuPercent
        self.physFootprintBytes = physFootprintBytes
        self.residentBytes = residentBytes
        self.threadCount = threadCount
    }

    /// Physical footprint in mebibytes, for the memory gauge.
    public var physFootprintMegabytes: Double {
        Double(physFootprintBytes) / 1_048_576
    }

    /// CPU% over the interval `previous` → `current`, with the memory and thread counts
    /// taken from `current`. Guards the two failure modes of a cumulative counter: a
    /// zero-length interval (division by zero) and a counter that rewound on pid reuse.
    public static func derive(from previous: VitalsReading, to current: VitalsReading) -> MetricSample {
        MetricSample(
            cpuPercent: cpuPercent(from: previous, to: current),
            physFootprintBytes: current.physFootprintBytes,
            residentBytes: current.residentBytes,
            threadCount: current.threadCount
        )
    }

    private static func cpuPercent(from previous: VitalsReading, to current: VitalsReading) -> Double {
        guard current.wallClockNanos > previous.wallClockNanos,
              current.cpuTimeNanos >= previous.cpuTimeNanos else { return 0 }
        let cpuDelta = current.cpuTimeNanos - previous.cpuTimeNanos
        let wallDelta = current.wallClockNanos - previous.wallClockNanos
        return Double(cpuDelta) / Double(wallDelta) * 100
    }
}
