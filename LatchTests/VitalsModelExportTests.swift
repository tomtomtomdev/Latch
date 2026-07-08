import Testing
import LatchDomain
@testable import Latch

/// The session-report export seam: `VitalsModel` assembles a shareable `SessionReport` from its
/// current session — the metric timeline, the alert log, the diagnostics that ran, and the live
/// provenance. The `NSSavePanel` + file write is a thin Humble Object in the view; this is the
/// testable core. (SPEC §3.1, §4, §8; PLAN slice 10)
@MainActor
struct VitalsModelExportTests {
    private let target = Target(id: "42", kind: .localMac, pid: 42, displayName: "Leaky")

    private func reading(cpu: UInt64, wall: UInt64, footprint: UInt64 = 0) -> VitalsReading {
        VitalsReading(
            cpuTimeNanos: cpu, physFootprintBytes: footprint, residentBytes: 0,
            threadCount: 0, energyNanojoules: 0, wallClockNanos: wall
        )
    }

    // The report carries this session's target and metric timeline.
    @Test func sessionReport_bundlesTargetAndTimeline() async {
        let source = FakeMetricsSource(readings: [
            reading(cpu: 0, wall: 0),
            reading(cpu: 500_000_000, wall: 1_000_000_000, footprint: 2_097_152),
        ])
        let model = VitalsModel(source: source, target: target, pid: 42)

        await model.poll()
        await model.poll()

        let report = model.sessionReport()
        #expect(report?.target.id == "42")
        #expect(report?.metrics.count == 1)
    }

    // Live provenance names the signals this stream actually polls (CPU, the memory-growth hint,
    // the energy estimate), all tagged live-poll. Network is absent without a nettop source.
    @Test func sessionReport_recordsLivePollProvenance() {
        let model = VitalsModel(source: FakeMetricsSource(readings: []), target: target, pid: 42)

        let live = liveSignals(of: model)
        #expect(live.contains(.cpuSpike))
        #expect(live.contains(.memoryLeak))
        #expect(live.contains(.battery))
        #expect(!live.contains(.networkIO))
    }

    // A wired network source adds the live networkIO provenance (nettop).
    @Test func sessionReport_includesNetworkProvenanceWhenWired() {
        let model = VitalsModel(
            source: FakeMetricsSource(readings: []),
            networkSource: FakeNetworkSource(readings: []),
            target: target, pid: 42
        )
        #expect(liveSignals(of: model).contains(.networkIO))
    }

    // A diagnostic that ran appears in the report, and `ExportReport` derives its deep-run provenance.
    @Test func sessionReport_includesRanDiagnosticsAndDeepProvenance() async {
        let leak = DiagnosticResult(
            kind: .leaks, summary: "1 leak",
            findings: [Finding(title: "X", byteCount: 16, instanceCount: 1)]
        )
        let model = VitalsModel(
            source: FakeMetricsSource(readings: []),
            leakChecker: FakeDiagnosticRunner(kind: .leaks, result: leak),
            target: target, pid: 42
        )

        await model.checkLeaks()

        let report = model.sessionReport()
        #expect(report?.diagnostics.contains { $0.kind == .leaks } == true)
        #expect(report?.provenance.contains { $0.signal == .memoryLeak && $0.mode == .deepRun } == true)
    }

    // No target → nothing to report.
    @Test func sessionReport_nilWithoutTarget() {
        let model = VitalsModel(source: FakeMetricsSource(readings: []), pid: 42)
        #expect(model.sessionReport() == nil)
    }

    private func liveSignals(of model: VitalsModel) -> [SignalKind] {
        (model.sessionReport()?.provenance ?? []).filter { $0.mode == .livePoll }.map(\.signal)
    }
}
