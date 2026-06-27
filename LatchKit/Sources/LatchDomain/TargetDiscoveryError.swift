// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Why target discovery failed. Like `DiagnosticError`, a failing tool is an expected outcome
/// to surface honestly (e.g. `devicectl` can't reach the Core Device daemon), not a crash.
/// (SPEC §1; PLAN slice 9)
public enum TargetDiscoveryError: Error, Equatable {
    /// The underlying tool exited non-zero; carries its exit code and stderr for the UI.
    case toolFailed(exitCode: Int32, message: String)
}
