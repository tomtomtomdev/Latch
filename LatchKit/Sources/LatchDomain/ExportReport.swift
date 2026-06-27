// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Use case: assemble a `SessionReport` from one session's pieces — the metric timeline, the
/// alert log, the diagnostic-run summaries, and the live-source provenance. Pure and
/// deterministic. Beyond bundling, it **derives** a deep-run provenance entry for each diagnostic
/// that ran, so the report is self-describing about how every figure was obtained (SPEC §8) —
/// the caller need only supply provenance for the live pollers it wired. (SPEC §3.1, §4; PLAN slice 10)
public struct ExportReport: Sendable {
    public init() {}

    public func callAsFunction(
        target: Target,
        metrics: [MetricSample],
        alerts: [Alert],
        diagnostics: [DiagnosticResult],
        liveProvenance: [MetricProvenance]
    ) -> SessionReport {
        SessionReport(
            target: target,
            metrics: metrics,
            alerts: alerts,
            diagnostics: diagnostics,
            provenance: liveProvenance + diagnostics.map(deepProvenance)
        )
    }

    /// The provenance of a deep, on-demand diagnostic: its signal, the diagnostic that produced
    /// it, run as a deep run (never a live poll — SPEC §1).
    private func deepProvenance(for diagnostic: DiagnosticResult) -> MetricProvenance {
        MetricProvenance(
            signal: diagnostic.kind.signal,
            source: diagnostic.kind.sourceLabel,
            mode: .deepRun
        )
    }
}

private extension DiagnosticKind {
    /// The health signal this diagnostic informs. (SPEC §3.3)
    var signal: SignalKind {
        switch self {
        case .leaks: .memoryLeak
        case .zombies: .zombies
        case .hitches: .hitch
        }
    }

    /// A human-readable label for the mechanism that backs this diagnostic. (SPEC §3.2)
    var sourceLabel: String {
        switch self {
        case .leaks: "Leaks"
        case .zombies: "Zombies (relaunch)"
        case .hitches: "Hitches / hangs"
        }
    }
}
