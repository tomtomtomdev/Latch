import Testing
import LatchDomain
@testable import Latch

@MainActor
struct VitalsModelZombieCheckTests {
    private let target = Target(
        id: "42", kind: .localMac, pid: 42,
        executablePath: "/Applications/Leaky.app/Contents/MacOS/Leaky", displayName: "Leaky"
    )

    private func model(zombieRunner: DiagnosticRunner? = nil, target: Target? = nil) -> VitalsModel {
        VitalsModel(
            source: FakeMetricsSource(readings: []),
            zombieRunner: zombieRunner,
            target: target ?? self.target,
            pid: 42
        )
    }

    private func zombieReport() -> DiagnosticResult {
        DiagnosticResult(
            kind: .zombies,
            summary: "1 zombie message detected",
            findings: [Finding(title: "-[LatchLeaky doWork]", byteCount: 0, instanceCount: 1)]
        )
    }

    private func fake(_ result: DiagnosticResult) -> FakeDiagnosticRunner {
        FakeDiagnosticRunner(kind: .zombies, requiresRelaunch: true, result: result)
    }

    // A successful relaunch-and-detect stores the zombie report for the dashboard. (PLAN slice 7)
    @Test func checkZombies_storesReportFromRunner() async {
        let model = model(zombieRunner: fake(zombieReport()))

        await model.checkZombies()

        #expect(model.zombieReport?.findings.first?.title == "-[LatchLeaky doWork]")
        #expect(model.zombieMessage == nil)
    }

    // A failed relaunch (couldn't exec) surfaces a message, never a crash or a stale report. (SPEC §1)
    @Test func checkZombies_recordsMessageWhenRunnerFails() async {
        let model = model(zombieRunner: FakeDiagnosticRunner(
            kind: .zombies, requiresRelaunch: true,
            failsWith: DiagnosticError.toolFailed(exitCode: 127, message: "No such file or directory")
        ))

        await model.checkZombies()

        #expect(model.zombieReport == nil)
        #expect(model.zombieMessage != nil)
    }

    // The action is gated honestly: it needs a runner AND an executable path to relaunch.
    // Without either, the UI hides the button rather than offering an impossible action. (SPEC §1)
    @Test func canCheckZombies_requiresRunnerAndExecutablePath() {
        let pathless = Target(id: "42", kind: .localMac, pid: 42, displayName: "no path")

        #expect(!model(zombieRunner: nil).canCheckZombies)
        #expect(!model(zombieRunner: fake(zombieReport()), target: pathless).canCheckZombies)
        #expect(model(zombieRunner: fake(zombieReport())).canCheckZombies)
    }
}
