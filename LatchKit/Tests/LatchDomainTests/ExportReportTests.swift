import Testing
import LatchDomain

/// Slice 10: `ExportReport` assembles a shareable session report (timeline + alert log +
/// diagnostic-run summaries + `.trace` paths) and records **provenance per metric** — which
/// source produced each signal, and whether it was a live poll or an on-demand deep run.
/// Pure Domain logic; serialization round-trips are exercised against the Data serializer.
/// (SPEC §3.1, §4, §8; PLAN slice 10)
struct ExportReportTests {
    private let target = Target(
        id: "p-501", kind: .localMac, pid: 501, executablePath: "/Apps/Demo", displayName: "Demo"
    )

    private func sample(
        cpu: Double = 10, footprint: UInt64 = 0,
        netIn: Double = 0, netOut: Double = 0, energy: Double = 0
    ) -> MetricSample {
        MetricSample(
            cpuPercent: cpu, physFootprintBytes: footprint, residentBytes: footprint,
            threadCount: 1, netInBytesPerSec: netIn, netOutBytesPerSec: netOut, energyWatts: energy
        )
    }

    private let cpuProvenance = MetricProvenance(
        signal: .cpuSpike, source: "proc_pid_rusage", mode: .livePoll
    )

    // The report carries the session verbatim: target, the metric timeline, the alert log,
    // and the diagnostic-run summaries (with their `.trace` paths intact).
    @Test func report_bundlesTimelineAlertsAndDiagnostics() {
        let samples = [sample(cpu: 12), sample(cpu: 99)]
        let alerts = [Alert(signal: .cpuSpike, severity: .warning, sample: samples[1])]
        let leak = DiagnosticResult(
            kind: .leaks, summary: "1 leak",
            findings: [Finding(title: "ROOT LEAK", byteCount: 32, instanceCount: 1)],
            tracePath: "/tmp/x.trace"
        )

        let report = ExportReport()(
            target: target, metrics: samples, alerts: alerts, diagnostics: [leak],
            liveProvenance: [cpuProvenance]
        )

        #expect(report.target == target)
        #expect(report.metrics == samples)
        #expect(report.alerts == alerts)
        #expect(report.diagnostics == [leak])
    }

    // Provenance per metric: the supplied live-source provenance is recorded, and a deep-run
    // provenance entry is *derived* for each diagnostic that ran (leaks → memoryLeak, deep).
    @Test func report_recordsProvenance_forLiveSourcesAndDerivedDeepRuns() {
        let leak = DiagnosticResult(kind: .leaks, summary: "1 leak", findings: [], tracePath: nil)

        let report = ExportReport()(
            target: target, metrics: [sample()], alerts: [], diagnostics: [leak],
            liveProvenance: [cpuProvenance]
        )

        #expect(report.provenance.contains(cpuProvenance))
        let deep = report.provenance.first { $0.mode == .deepRun }
        #expect(deep?.signal == .memoryLeak)
    }

    // The Markdown summary surfaces the headline facts a shared report needs: the target, the
    // sample count, each metric's provenance source, the alerts, and each diagnostic summary
    // with its trace path.
    @Test func markdownSummary_listsTargetProvenanceAlertsAndDiagnostics() {
        let samples = [sample(cpu: 12, footprint: 10_485_760), sample(cpu: 150, footprint: 20_971_520)]
        let alerts = [Alert(signal: .cpuSpike, severity: .warning, sample: samples[1])]
        let leak = DiagnosticResult(
            kind: .leaks, summary: "1 leak found",
            findings: [Finding(title: "ROOT LEAK", byteCount: 32, instanceCount: 2)],
            tracePath: "/tmp/x.trace"
        )

        let md = ExportReport()(
            target: target, metrics: samples, alerts: alerts, diagnostics: [leak],
            liveProvenance: [cpuProvenance]
        ).markdownSummary

        #expect(md.contains("Demo"))
        #expect(md.contains("Samples: 2"))
        #expect(md.contains("proc_pid_rusage"))
        #expect(md.contains("cpuSpike"))
        #expect(md.contains("1 leak found"))
        #expect(md.contains("/tmp/x.trace"))
    }

    // An empty session reports honestly — it never implies data it doesn't have. (SPEC §1)
    @Test func markdownSummary_isHonest_forEmptySession() {
        let md = ExportReport()(
            target: target, metrics: [], alerts: [], diagnostics: [], liveProvenance: []
        ).markdownSummary

        #expect(md.contains("No samples"))
        #expect(md.contains("No alerts"))
        #expect(md.contains("No diagnostics"))
    }
}
