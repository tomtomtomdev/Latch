// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// One raw, point-in-time reading of a process's network counters as the OS reports
/// them. Bytes are *cumulative* since the socket was opened, so they are meaningless
/// alone — a per-second rate is derived from the delta between two readings (see
/// `NetworkRate.derive`). The Data adapter that fills this from `nettop` owns the
/// parsing; this value type keeps the rate derivation testable. (SPEC §3.2, §4; PLAN slice 4)
public struct NetworkReading: Sendable, Equatable {
    /// Cumulative bytes received.
    public let bytesIn: UInt64
    /// Cumulative bytes sent.
    public let bytesOut: UInt64
    /// Monotonic clock value captured at read time, in nanoseconds. Used only for the
    /// wall-clock delta between two readings, so its epoch is irrelevant.
    public let wallClockNanos: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64, wallClockNanos: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.wallClockNanos = wallClockNanos
    }
}
