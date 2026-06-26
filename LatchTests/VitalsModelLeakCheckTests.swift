import Testing
import LatchDomain
@testable import Latch

@MainActor
struct VitalsModelLeakCheckTests {
    private let target = Target(id: "42", kind: .localMac, pid: 42, displayName: "leaker")

    private func model(
        leakChecker: DiagnosticRunner? = nil, traceRecorder: DiagnosticRunner? = nil
    ) -> VitalsModel {
        VitalsModel(
            source: FakeMetricsSource(readings: []),
            leakChecker: leakChecker,
            traceRecorder: traceRecorder,
            target: target,
            pid: 42
        )
    }

    private func report(findings: [Finding]) -> DiagnosticResult {
        DiagnosticResult(kind: .leaks, summary: "1 leak for 16 total leaked bytes", findings: findings)
    }

    // A successful leak check stores the report (findings + summary) for the dashboard. (PLAN slice 6)
    @Test func checkLeaks_storesReportFromRunner() async {
        let finding = Finding(title: "ROOT LEAK: <malloc in foo>", byteCount: 16, instanceCount: 1)
        let model = model(leakChecker: FakeDiagnosticRunner(result: report(findings: [finding])))

        await model.checkLeaks()

        #expect(model.leakReport?.findings == [finding])
        #expect(model.leakMessage == nil)
    }

    // A failing run (e.g. target exited) surfaces a message, never a crash or a stale report. (SPEC §1)
    @Test func checkLeaks_recordsMessageWhenRunnerFails() async {
        let model = model(leakChecker: FakeDiagnosticRunner(failsWith: DiagnosticError.toolFailed(
            exitCode: 255, message: "no longer running"
        )))

        await model.checkLeaks()

        #expect(model.leakReport == nil)
        #expect(model.leakMessage != nil)
    }

    // Recording a deep trace stores the .trace path so the UI can offer "open in Instruments". (PLAN slice 6)
    @Test func recordLeakTrace_storesTracePathFromRecorder() async {
        let recorded = DiagnosticResult(
            kind: .leaks, summary: "Recorded", findings: [], tracePath: "/tmp/Latch-leaks-42.trace"
        )
        let model = model(traceRecorder: FakeDiagnosticRunner(result: recorded))

        await model.recordLeakTrace()

        #expect(model.traceResult?.tracePath == "/tmp/Latch-leaks-42.trace")
    }

    // Without a leak runner wired, the action is unavailable — the UI hides the button rather
    // than offering a capability that does not exist. (SPEC §1)
    @Test func canCheckLeaks_isFalseWithoutARunner() {
        #expect(!model().canCheckLeaks)
        #expect(model(leakChecker: FakeDiagnosticRunner(result: report(findings: []))).canCheckLeaks)
    }
}
