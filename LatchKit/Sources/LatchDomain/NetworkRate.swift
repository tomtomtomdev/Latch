// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// A derived network throughput: bytes per second in each direction, computed from the
/// delta between two cumulative `NetworkReading`s. Pure and deterministic so the rate
/// math is TDD'd first (SPEC §6). (PLAN slice 4)
public struct NetworkRate: Sendable, Equatable {
    public let inBytesPerSec: Double
    public let outBytesPerSec: Double

    public static let zero = NetworkRate(inBytesPerSec: 0, outBytesPerSec: 0)

    public init(inBytesPerSec: Double, outBytesPerSec: Double) {
        self.inBytesPerSec = inBytesPerSec
        self.outBytesPerSec = outBytesPerSec
    }

    /// Throughput over the interval `previous` → `current`. Guards the two failure modes
    /// of a cumulative counter: a zero-length interval (division by zero) and a counter
    /// that rewound (pid reuse, `nettop` reset) — either yields a zero rate.
    public static func derive(from previous: NetworkReading, to current: NetworkReading) -> NetworkRate {
        guard current.wallClockNanos > previous.wallClockNanos,
              current.bytesIn >= previous.bytesIn,
              current.bytesOut >= previous.bytesOut else { return .zero }
        let seconds = Double(current.wallClockNanos - previous.wallClockNanos) / 1_000_000_000
        return NetworkRate(
            inBytesPerSec: Double(current.bytesIn - previous.bytesIn) / seconds,
            outBytesPerSec: Double(current.bytesOut - previous.bytesOut) / seconds
        )
    }
}
