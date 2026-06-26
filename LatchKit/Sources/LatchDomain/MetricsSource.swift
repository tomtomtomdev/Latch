// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Reads a single raw vitals snapshot for a pid. Domain owns the abstraction; the Data
/// layer supplies a libproc-backed implementation. Returns cumulative counters — the
/// caller derives a `MetricSample` (CPU%) from successive readings. (SPEC §3.2; PLAN slice 2)
public protocol MetricsSource: Sendable {
    /// One point-in-time reading for `pid`. Throws if the process is gone or unreadable
    /// (e.g. exited, or not same-UID — only same-UID targets are attachable, SPEC §1).
    func sample(pid: Int32) throws -> VitalsReading
}
