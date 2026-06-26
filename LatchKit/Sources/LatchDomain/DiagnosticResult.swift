// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// One leaked allocation (or a group of identical ones sharing an allocation site) reported
/// by a leak diagnostic. `backtrace` is non-empty only when the target was launched with
/// `MallocStackLogging` — that is the part that says *where* the leak came from. (SPEC §1, §3.3)
public struct Finding: Sendable, Equatable {
    /// A human-readable signature: the leaked type / allocation site (e.g.
    /// `ROOT LEAK: <malloc in make_leak>`), or just the block address when no symbol is known.
    public let title: String
    /// Bytes leaked for this finding (sum across its instances).
    public let byteCount: Int
    /// How many identical leaked blocks share this allocation site.
    public let instanceCount: Int
    /// Allocation backtrace frames, outermost first. Empty without launch-time
    /// `MallocStackLogging`.
    public let backtrace: [String]

    public init(title: String, byteCount: Int, instanceCount: Int, backtrace: [String] = []) {
        self.title = title
        self.byteCount = byteCount
        self.instanceCount = instanceCount
        self.backtrace = backtrace
    }
}

/// The outcome of a deep diagnostic run: a one-line `summary`, any structured `findings`, and
/// the path to the recorded `.trace` bundle when the run produced one (so the user can open
/// the full analysis in Instruments — Latch summarizes, it does not re-implement the viewer).
/// (SPEC §1, §4; PLAN slice 6)
public struct DiagnosticResult: Sendable, Equatable {
    public let kind: DiagnosticKind
    public let summary: String
    public let findings: [Finding]
    public let tracePath: String?

    public init(kind: DiagnosticKind, summary: String, findings: [Finding], tracePath: String? = nil) {
        self.kind = kind
        self.summary = summary
        self.findings = findings
        self.tracePath = tracePath
    }

    /// Whether any finding carries an allocation backtrace. `false` while findings exist is the
    /// cue to surface the `MallocStackLogging` caveat. (SPEC §1)
    public var hasBacktraces: Bool { findings.contains { !$0.backtrace.isEmpty } }

    /// Whether the run found anything — distinguishes a clean run from leaks-without-stacks.
    public var hasFindings: Bool { !findings.isEmpty }
}
