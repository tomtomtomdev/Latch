// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Reads a single raw network-counter snapshot for a pid. Domain owns the abstraction;
/// the Data layer supplies a `nettop`-backed implementation. Returns cumulative byte
/// counters — the caller derives a `NetworkRate` from successive readings. Async because
/// the backing tool shells out. (SPEC §3.2; PLAN slice 4)
public protocol NetworkSource: Sendable {
    /// Cumulative network bytes for `pid` at this instant. A process with no open sockets
    /// reads as zero bytes (not an error) — death detection is the vitals source's job.
    func sample(pid: Int32) async throws -> NetworkReading
}
