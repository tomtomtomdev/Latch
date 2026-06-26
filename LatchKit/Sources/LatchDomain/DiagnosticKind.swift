// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// The kind of deep, on-demand diagnostic a `DiagnosticRunner` performs. Only `.leaks`
/// exists today; `.zombies`, `.hitch`, etc. arrive with their slices rather than as
/// speculative cases. (SPEC §3.1; PLAN slices 6–8)
public enum DiagnosticKind: Sendable, Equatable {
    case leaks
}
