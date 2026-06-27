// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// The kind of deep, on-demand diagnostic a `DiagnosticRunner` performs. Cases arrive with
/// their slices rather than as speculative stubs; `.hitch`, `.allocations`, etc. land later.
/// (SPEC §3.1; PLAN slices 6–8)
public enum DiagnosticKind: Sendable, Equatable {
    case leaks
    /// Over-released objects, detected by relaunching the target under `NSZombieEnabled`.
    /// Cannot attach to a running process — see `DiagnosticRunner.requiresRelaunch`. (SPEC §1)
    case zombies
    /// Main-thread hitches/hangs, found by sampling the running process (`sample <pid>`) and
    /// flagging a stalled main-thread stack, or by recording a deep `Time Profiler` trace.
    /// (SPEC §3.3; PLAN slice 8)
    case hitches
}
