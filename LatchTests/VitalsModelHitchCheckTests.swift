import Testing
import LatchDomain
@testable import Latch

@MainActor
struct VitalsModelHitchCheckTests {
    private let target = Target(id: "42", kind: .localMac, pid: 42, displayName: "Worker")

    private func model(
        hitchRunner: DiagnosticRunner? = nil,
        hitchTraceRecorder: DiagnosticRunner? = nil,
        target: Target? = nil
    ) -> VitalsModel {
        VitalsModel(
            source: FakeMetricsSource(readings: []),
            hitchRunner: hitchRunner,
            hitchTraceRecorder: hitchTraceRecorder,
            target: target ?? self.target,
            pid: 42
        )
    }

    private func hitchReport() -> DiagnosticResult {
        DiagnosticResult(
            kind: .hitches,
            summary: "1 main-thread stall — longest ~920 ms in __semwait_signal.",
            findings: [Finding(
                title: "__semwait_signal", byteCount: 0, instanceCount: 92,
                backtrace: ["start", "nanosleep", "__semwait_signal"]
            )]
        )
    }

    private func fake(_ result: DiagnosticResult) -> FakeDiagnosticRunner {
        FakeDiagnosticRunner(kind: .hitches, result: result)
    }

    // A sample-based hitch check stores the report (stall findings + summary). (PLAN slice 8)
    @Test func checkHitches_storesReportFromRunner() async {
        let model = model(hitchRunner: fake(hitchReport()))

        await model.checkHitches()

        #expect(model.hitchReport?.findings.first?.title == "__semwait_signal")
        #expect(model.hitchMessage == nil)
    }

    // A failed sample run (process gone) surfaces a message, never a crash or stale report. (SPEC §1)
    @Test func checkHitches_recordsMessageWhenRunnerFails() async {
        let model = model(hitchRunner: FakeDiagnosticRunner(
            kind: .hitches,
            failsWith: DiagnosticError.toolFailed(exitCode: 255, message: "no longer running")
        ))

        await model.checkHitches()

        #expect(model.hitchReport == nil)
        #expect(model.hitchMessage != nil)
    }

    // Recording a Time Profiler trace stores the .trace path so the UI can offer
    // "open in Instruments". (PLAN slice 8)
    @Test func recordHitchTrace_storesTracePathFromRecorder() async {
        let recorded = DiagnosticResult(
            kind: .hitches, summary: "Recorded", findings: [], tracePath: "/tmp/Latch-hitches-42.trace"
        )
        let model = model(hitchTraceRecorder: fake(recorded))

        await model.recordHitchTrace()

        #expect(model.hitchTraceResult?.tracePath == "/tmp/Latch-hitches-42.trace")
    }

    // The quick hitch check is gated honestly on a wired runner + a target. (SPEC §1)
    @Test func canCheckHitches_requiresRunnerAndTarget() {
        #expect(!model(hitchRunner: nil).canCheckHitches)
        #expect(model(hitchRunner: fake(hitchReport())).canCheckHitches)
    }
}
