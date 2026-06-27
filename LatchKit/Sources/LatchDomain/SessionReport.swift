// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Whether a value came from cheap **live polling** or an on-demand **deep run** — SPEC §1's
/// two operating modes per signal, which the UI must never conflate. Carried in provenance so a
/// shared report stays honest about how each figure was obtained. (SPEC §1, §8)
public enum SamplingMode: String, Sendable, Equatable, Codable {
    case livePoll
    case deepRun
}

/// Provenance for one metric in a session: which signal it is, which mechanism/adapter produced
/// it, and whether it was a live poll or a deep run. SPEC §4 requires the data model be
/// provenance-aware ("every value records which adapter produced it"); §8 requires every surfaced
/// figure show its provenance. Recorded once per source at the report level — not per sample,
/// since the source is constant across a session and per-sample tagging would bloat the timeline.
public struct MetricProvenance: Sendable, Equatable, Codable {
    public let signal: SignalKind
    /// The producing mechanism/adapter, as a human-readable label (e.g. `proc_pid_rusage`,
    /// `nettop`, `Leaks`). A free-form string so the Domain stays decoupled from Data class names.
    public let source: String
    public let mode: SamplingMode

    public init(signal: SignalKind, source: String, mode: SamplingMode) {
        self.signal = signal
        self.source = source
        self.mode = mode
    }
}

/// A shareable snapshot of one latching session: the metric timeline, the alert log, the
/// diagnostic-run summaries (with their `.trace` paths), and the per-metric provenance. Codable
/// so the Data layer can serialize it to a JSON bundle; it also renders a human-readable Markdown
/// summary. Assembled by `ExportReport`. (SPEC §3.1, §4; PLAN slice 10)
public struct SessionReport: Sendable, Equatable, Codable {
    public let target: Target
    public let metrics: [MetricSample]
    public let alerts: [Alert]
    public let diagnostics: [DiagnosticResult]
    public let provenance: [MetricProvenance]

    public init(
        target: Target,
        metrics: [MetricSample],
        alerts: [Alert],
        diagnostics: [DiagnosticResult],
        provenance: [MetricProvenance]
    ) {
        self.target = target
        self.metrics = metrics
        self.alerts = alerts
        self.diagnostics = diagnostics
        self.provenance = provenance
    }

    /// A human-readable Markdown digest of the session — the optional summary that ships beside
    /// the JSON bundle. Every section states honestly when it has nothing to report. (SPEC §1)
    public var markdownSummary: String {
        ([header] + overviewSection + provenanceSection + alertsSection + diagnosticsSection)
            .joined(separator: "\n")
    }

    private var header: String { "# Latch Session Report — \(target.displayName)\n" }

    private var overviewSection: [String] {
        var lines = [
            "- Target: \(target.displayName) (\(target.kind), pid \(target.pid.map(String.init) ?? "—"))",
            "- Samples: \(metrics.count)",
        ]
        if metrics.isEmpty {
            lines.append("- No samples recorded.")
        } else {
            lines.append("- Peak CPU: \(oneDecimal(peak(\.cpuPercent)))% of one core")
            lines.append("- Peak memory: \(oneDecimal(peak(\.physFootprintMegabytes))) MB")
            lines.append("- Peak network: \(oneDecimal(peak(\.networkMegabytesPerSecond))) MB/s")
            lines.append("- Peak energy: \(oneDecimal(peak(\.energyWatts))) W (estimate)")
        }
        return lines + [""]
    }

    private var provenanceSection: [String] {
        var lines = ["## Provenance"]
        if provenance.isEmpty {
            lines.append("No metric sources recorded.")
        } else {
            lines.append("| Signal | Source | Mode |")
            lines.append("| --- | --- | --- |")
            lines += provenance.map { "| \($0.signal.rawValue) | \($0.source) | \($0.mode.rawValue) |" }
        }
        return lines + [""]
    }

    private var alertsSection: [String] {
        var lines = ["## Alerts"]
        if alerts.isEmpty {
            lines.append("No alerts fired.")
        } else {
            lines += alerts.map { "- \($0.signal.rawValue) (\($0.severity.rawValue))" }
        }
        return lines + [""]
    }

    private var diagnosticsSection: [String] {
        var lines = ["## Diagnostics"]
        if diagnostics.isEmpty {
            lines.append("No diagnostics run.")
            return lines
        }
        for diagnostic in diagnostics {
            lines.append("### \(diagnostic.kind.rawValue) — \(diagnostic.summary)")
            if let tracePath = diagnostic.tracePath {
                lines.append("- Trace: \(tracePath)")
            }
            lines += diagnostic.findings.map {
                "- \($0.title) — \($0.instanceCount) instance(s), \($0.byteCount) bytes"
            }
        }
        return lines
    }

    private func peak(_ value: (MetricSample) -> Double) -> Double {
        metrics.map(value).max() ?? 0
    }
}

/// Renders a non-negative value to one decimal place without Foundation (the Domain imports
/// nothing). Integer arithmetic on the value scaled by ten.
private func oneDecimal(_ value: Double) -> String {
    let scaled = Int((value * 10).rounded())
    return "\(scaled / 10).\(scaled % 10)"
}
