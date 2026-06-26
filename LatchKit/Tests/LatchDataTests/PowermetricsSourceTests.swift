import Testing
import Foundation
import LatchDomain
@testable import LatchData

struct PowermetricsSourceTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func source(
        stdout: String, exitCode: Int32 = 0
    ) -> (PowermetricsSource, RecordingCommandRunner) {
        let runner = RecordingCommandRunner(
            result: CommandResult(stdout: stdout, stderr: "", exitCode: exitCode)
        )
        return (PowermetricsSource(commandRunner: runner), runner)
    }

    // The tasks-sampler plist carries one row per process; the requested pid's energy impact
    // is pulled from its `energy_impact` key. (PLAN slice 5)
    @Test func measuredEnergyImpact_parsesImpactForThePid() async throws {
        let (powermetrics, _) = source(stdout: try fixture("powermetrics-tasks"))

        let impact = try await powermetrics.measuredEnergyImpact(pid: 148)

        #expect(impact == 42.57)
    }

    // A pid with no row in the sample window is reported distinctly, not as a silent zero —
    // the model degrades to the estimate rather than charting a bogus measurement. (SPEC §6)
    @Test func measuredEnergyImpact_throwsWhenPidNotInSample() async throws {
        let (powermetrics, _) = source(stdout: try fixture("powermetrics-tasks"))

        await #expect(throws: EnergyMeasurementError.processNotFound(pid: 999_999)) {
            try await powermetrics.measuredEnergyImpact(pid: 999_999)
        }
    }

    // A non-zero exit (the unprivileged "must be run as the superuser" case) is the degrade
    // trigger: it surfaces as `.unavailable`, never as parsed garbage. (SPEC §1, §5)
    @Test func measuredEnergyImpact_throwsUnavailableWhenToolExitsNonZero() async throws {
        let (powermetrics, _) = source(stdout: "", exitCode: 1)

        await #expect(throws: EnergyMeasurementError.unavailable) {
            try await powermetrics.measuredEnergyImpact(pid: 148)
        }
    }

    // The adapter runs exactly the documented command — flags pinned so a regression is
    // caught here, not at runtime against a root-only tool. (PLAN slice 5; SPEC §3.2)
    @Test func measuredEnergyImpact_invokesPowermetricsTasksSamplerInPlist() async throws {
        let (powermetrics, runner) = source(stdout: try fixture("powermetrics-tasks"))

        _ = try await powermetrics.measuredEnergyImpact(pid: 350)

        #expect(runner.executablePath == "/usr/bin/powermetrics")
        #expect(runner.arguments == [
            "--samplers", "tasks", "--show-process-energy", "-f", "plist", "-n", "1", "-i", "1000",
        ])
    }
}
