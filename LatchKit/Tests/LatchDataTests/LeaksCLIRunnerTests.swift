import Testing
import Foundation
import LatchDomain
@testable import LatchData

struct LeaksCLIRunnerTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func runner(
        stdout: String, exitCode: Int32 = 0
    ) -> (LeaksCLIRunner, RecordingCommandRunner) {
        let command = RecordingCommandRunner(
            result: CommandResult(stdout: stdout, stderr: "", exitCode: exitCode)
        )
        return (LeaksCLIRunner(commandRunner: command), command)
    }

    private let target = Target(id: "4242", kind: .localMac, pid: 4242, displayName: "leaker")

    // A clean process reports zero leaks and no findings — exit code 0, distinct from a run
    // that found leaks. (PLAN slice 6)
    @Test func run_reportsNoLeaks_forACleanProcess() async throws {
        let (leaks, _) = runner(stdout: try fixture("leaks-none"), exitCode: 0)

        let result = try await leaks.run(target, options: DiagnosticOptions())

        #expect(!result.hasFindings)
        #expect(result.summary == "0 leaks for 0 total leaked bytes")
    }

    // With MallocStackLogging, leaks are grouped by allocation site, each carrying an
    // instance count, its leaked bytes, and the backtrace that says where it came from.
    @Test func run_extractsGroupedFindingsWithBacktraces() async throws {
        let (leaks, _) = runner(stdout: try fixture("leaks-with-stacks"), exitCode: 1)

        let result = try await leaks.run(target, options: DiagnosticOptions())

        #expect(result.summary == "4 leaks for 512 total leaked bytes")
        #expect(result.findings.count == 2)
        let makeLeak = try #require(result.findings.first)
        #expect(makeLeak.title == "ROOT LEAK: <malloc in make_leak>")
        #expect(makeLeak.instanceCount == 3)
        #expect(makeLeak.byteCount == 480)
        #expect(makeLeak.backtrace.count == 4)
        #expect(makeLeak.backtrace.contains { $0.contains("make_leak") })
        #expect(result.hasBacktraces)
    }

    // Without launch-time MallocStackLogging there are no stacks: the leaked blocks are still
    // reported (so the leak is visible) but the report knows backtraces are absent — the cue
    // for the UI's MallocStackLogging caveat. (SPEC §1)
    @Test func run_reportsLeaksWithoutBacktraces_whenMallocStackLoggingOff() async throws {
        let (leaks, _) = runner(stdout: try fixture("leaks-without-stacks"), exitCode: 1)

        let result = try await leaks.run(target, options: DiagnosticOptions())

        #expect(result.summary == "4 leaks for 416 total leaked bytes")
        #expect(result.findings.count == 4)
        #expect(!result.hasBacktraces)
        #expect(result.hasFindings)
    }

    // Exit code 1 means "leaks found" — a success for us. Only exit codes above 1 are tool
    // errors, surfaced honestly instead of parsed as garbage. (man leaks: 0 none, 1 found, >1 error)
    @Test func run_throwsToolFailed_whenExitCodeAboveOne() async throws {
        let (leaks, _) = runner(stdout: "", exitCode: 255)

        await #expect(throws: DiagnosticError.self) {
            try await leaks.run(target, options: DiagnosticOptions())
        }
    }

    // The adapter runs exactly `leaks <pid>` — pinned so a flag regression is caught here.
    @Test func run_invokesLeaksWithThePID() async throws {
        let (leaks, command) = runner(stdout: try fixture("leaks-none"), exitCode: 0)

        _ = try await leaks.run(target, options: DiagnosticOptions())

        #expect(command.executablePath == "/usr/bin/leaks")
        #expect(command.arguments == ["4242"])
    }

    // A target without a pid cannot be examined — reported distinctly, never as an empty run.
    @Test func run_throwsWhenTargetHasNoPID() async throws {
        let (leaks, _) = runner(stdout: "", exitCode: 0)
        let pidless = Target(id: "x", kind: .localMac, displayName: "no pid")

        await #expect(throws: DiagnosticError.targetHasNoPID) {
            try await leaks.run(pidless, options: DiagnosticOptions())
        }
    }
}
