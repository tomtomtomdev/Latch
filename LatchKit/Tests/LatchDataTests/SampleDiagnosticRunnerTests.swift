import Testing
import Foundation
import LatchDomain
@testable import LatchData

struct SampleDiagnosticRunnerTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func runner(
        stdout: String = "", stderr: String = "", exitCode: Int32 = 0
    ) -> (SampleDiagnosticRunner, RecordingCommandRunner) {
        let command = RecordingCommandRunner(
            result: CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
        )
        return (SampleDiagnosticRunner(commandRunner: command), command)
    }

    private let target = Target(id: "4242", kind: .localMac, pid: 4242, displayName: "Worker")

    // sample attaches to a running same-UID process — no relaunch (unlike Zombies). (SPEC §1)
    @Test func kindIsHitchesAndDoesNotRequireRelaunch() {
        let (sampler, _) = runner()
        #expect(sampler.kind == .hitches)
        #expect(!sampler.requiresRelaunch)
    }

    // The runner invokes the verified same-UID command `sample <pid> <seconds> <interval-ms>`
    // (works without root, unlike spindump — verified on macOS 26.2). (SPEC §1; PLAN slice 8)
    @Test func run_samplesWithTheVerifiedCommand() async throws {
        let (sampler, command) = runner(stdout: try fixture("sample-responsive"))

        _ = try await sampler.run(target, options: DiagnosticOptions(timeLimit: .seconds(3)))

        #expect(command.executablePath == "/usr/bin/sample")
        #expect(command.arguments == ["4242", "3", "10"])
    }

    // A main thread wedged in one stack across the run (sleep → __semwait_signal, 92 samples ×
    // 10 ms = 920 ms) is flagged as a hang: the leaf is named and the wedged stack is carried.
    // (SPEC §3.3; PLAN slice 8)
    @Test func run_flagsWedgedMainThreadAsHang() async throws {
        let (sampler, _) = runner(stdout: try fixture("sample-hang"))

        let result = try await sampler.run(target, options: DiagnosticOptions())

        #expect(result.kind == .hitches)
        #expect(result.hasFindings)
        let finding = try #require(result.findings.first)
        #expect(finding.title == "__semwait_signal")
        #expect(finding.instanceCount == 92)
        #expect(finding.backtrace.contains { $0.contains("nanosleep") })
    }

    // A responsive main thread — its call tree branches into many short-lived leaves, none
    // wedged ≥ the threshold — reports no hang, even though an *internal* frame accumulated
    // many samples. High-count internal frames are not leaves; only a wedged leaf is a stall.
    // (SPEC §1, §3.3)
    @Test func run_reportsNoHang_forResponsiveMainThread() async throws {
        let (sampler, _) = runner(stdout: try fixture("sample-responsive"))

        let result = try await sampler.run(target, options: DiagnosticOptions())

        #expect(!result.hasFindings)
        #expect(result.summary.localizedCaseInsensitiveContains("no main-thread stall"))
    }

    // sample exits 255 when the process is gone — surfaced honestly, never parsed as "no hang".
    // (SPEC §1)
    @Test func run_throwsToolFailed_whenSampleCannotExamineProcess() async {
        let (sampler, _) = runner(
            stderr: "sample cannot examine process 4242 because it no longer appears to be running.",
            exitCode: 255
        )

        await #expect(throws: DiagnosticError.self) {
            try await sampler.run(target, options: DiagnosticOptions())
        }
    }

    // No pid, nothing to sample. (SPEC §3.1)
    @Test func run_throwsTargetHasNoPID_whenPidMissing() async {
        let (sampler, _) = runner()
        let pidless = Target(id: "x", kind: .localMac, pid: nil, displayName: "no pid")

        await #expect(throws: DiagnosticError.targetHasNoPID) {
            try await sampler.run(pidless, options: DiagnosticOptions())
        }
    }
}
