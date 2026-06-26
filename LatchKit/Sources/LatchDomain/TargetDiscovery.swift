// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Enumerates targets the user may latch onto. Domain owns the abstraction; the Data
/// layer supplies a libproc-backed implementation. Device enumeration is added in the
/// iOS slice. (SPEC §3.1, §3.2; PLAN slice 1)
public protocol TargetDiscovery: Sendable {
    /// Same-UID local macOS processes — the only ones a debugger-entitled tool can
    /// attach to. (SPEC §1)
    func localProcesses() async throws -> [Target]
}
