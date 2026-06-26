// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// A deep, on-demand diagnostic over a target — the "deep run" mode from SPEC §1, distinct
/// from the cheap live polling. Domain owns the abstraction; the Data layer supplies
/// implementations (`LeaksCLIRunner`, `XctraceDiagnosticRunner`). (SPEC §3.1; PLAN slice 6)
public protocol DiagnosticRunner: Sendable {
    var kind: DiagnosticKind { get }
    /// `true` for diagnostics that must launch the target under instrumentation and therefore
    /// cannot attach to a running process (e.g. Zombies). Leak runners attach, so this is
    /// `false`. (SPEC §1)
    var requiresRelaunch: Bool { get }
    func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult
}

/// Knobs for a diagnostic run. Minimal by design — only `timeLimit` (used by trace-recording
/// runners to bound a record) exists today; more arrive when a runner needs them. (SPEC §3.1)
public struct DiagnosticOptions: Sendable, Equatable {
    /// How long a trace-recording run captures before stopping.
    public var timeLimit: Duration

    public init(timeLimit: Duration = .seconds(10)) {
        self.timeLimit = timeLimit
    }
}

/// Why a diagnostic run failed. A failing tool is an expected outcome to surface honestly
/// (e.g. the entitlement wall when `xctrace` cannot acquire the task port), not a crash.
/// (SPEC §1)
public enum DiagnosticError: Error, Equatable {
    /// The underlying tool exited non-zero; carries its exit code and stderr for the UI.
    case toolFailed(exitCode: Int32, message: String)
    /// The target carries no pid to attach to (should not happen for a local mac process).
    case targetHasNoPID
}
