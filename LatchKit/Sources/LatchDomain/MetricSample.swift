// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// A derived, display-ready vitals sample for one polling tick: CPU% computed from the
/// delta between two raw readings, plus the latest memory and thread figures. This is
/// the entity the dashboard charts and thresholds consume. Network, disk, and energy
/// fields from SPEC §4 arrive in later slices — only the live mem+CPU signals exist
/// here. (SPEC §4; PLAN slice 2)
public struct MetricSample: Sendable, Equatable, Codable {
    /// CPU usage as a percentage of **one core**: 100 means one core fully busy, 200
    /// means two. Matches the "% of one core" threshold in SPEC §3.3.
    public let cpuPercent: Double
    public let physFootprintBytes: UInt64
    public let residentBytes: UInt64
    public let threadCount: Int
    /// Network throughput at this tick, derived from `nettop` byte deltas (0 until a
    /// `NetworkRate` is attached via `withNetwork`). (SPEC §4; PLAN slice 4)
    public let netInBytesPerSec: Double
    public let netOutBytesPerSec: Double
    /// The live energy *estimate* in watts, derived from the `ri_energy_nj` delta. Always
    /// available (no root) — `powermetrics` measured energy is a separate, on-demand,
    /// higher-fidelity figure surfaced alongside it, not folded in here. (SPEC §3.3; PLAN slice 5)
    public let energyWatts: Double

    public init(
        cpuPercent: Double,
        physFootprintBytes: UInt64,
        residentBytes: UInt64,
        threadCount: Int,
        netInBytesPerSec: Double = 0,
        netOutBytesPerSec: Double = 0,
        energyWatts: Double = 0
    ) {
        self.cpuPercent = cpuPercent
        self.physFootprintBytes = physFootprintBytes
        self.residentBytes = residentBytes
        self.threadCount = threadCount
        self.netInBytesPerSec = netInBytesPerSec
        self.netOutBytesPerSec = netOutBytesPerSec
        self.energyWatts = energyWatts
    }

    /// Physical footprint in mebibytes, for the memory gauge.
    public var physFootprintMegabytes: Double {
        Double(physFootprintBytes) / 1_048_576
    }

    /// Combined in+out throughput in **decimal** megabytes per second — the figure the
    /// network threshold compares against ("> 5 MB/s", SPEC §3.3). Network throughput is
    /// quoted in decimal MB by convention, so this uses 1_000_000, not 1_048_576.
    public var networkMegabytesPerSecond: Double {
        (netInBytesPerSec + netOutBytesPerSec) / 1_000_000
    }

    /// A copy of this sample with `rate` attached. The libproc vitals (CPU/mem/threads)
    /// and the `nettop` throughput come from independent sources; the model composes them
    /// into one sample per tick. (SPEC §3.2; PLAN slice 4)
    public func withNetwork(_ rate: NetworkRate) -> MetricSample {
        MetricSample(
            cpuPercent: cpuPercent,
            physFootprintBytes: physFootprintBytes,
            residentBytes: residentBytes,
            threadCount: threadCount,
            netInBytesPerSec: rate.inBytesPerSec,
            netOutBytesPerSec: rate.outBytesPerSec,
            energyWatts: energyWatts
        )
    }

    /// CPU% and the energy estimate over the interval `previous` → `current`, with the
    /// memory and thread counts taken from `current`. Both rates guard the two failure modes
    /// of a cumulative counter: a zero-length interval (division by zero) and a counter that
    /// rewound on pid reuse.
    public static func derive(from previous: VitalsReading, to current: VitalsReading) -> MetricSample {
        MetricSample(
            cpuPercent: cpuPercent(from: previous, to: current),
            physFootprintBytes: current.physFootprintBytes,
            residentBytes: current.residentBytes,
            threadCount: current.threadCount,
            energyWatts: energyWatts(from: previous, to: current)
        )
    }

    private static func cpuPercent(from previous: VitalsReading, to current: VitalsReading) -> Double {
        rate(from: previous, to: current, counter: \.cpuTimeNanos).map { $0 * 100 } ?? 0
    }

    /// Power in watts: nanojoules per nanosecond is exactly joules per second.
    private static func energyWatts(from previous: VitalsReading, to current: VitalsReading) -> Double {
        rate(from: previous, to: current, counter: \.energyNanojoules) ?? 0
    }

    /// The per-nanosecond rate of a cumulative `counter` over the interval. `nil` when the
    /// interval is zero-length or the counter rewound (pid reuse) — callers map that to 0.
    private static func rate(
        from previous: VitalsReading,
        to current: VitalsReading,
        counter: (VitalsReading) -> UInt64
    ) -> Double? {
        guard current.wallClockNanos > previous.wallClockNanos,
              counter(current) >= counter(previous) else { return nil }
        let delta = counter(current) - counter(previous)
        let wallDelta = current.wallClockNanos - previous.wallClockNanos
        return Double(delta) / Double(wallDelta)
    }
}
