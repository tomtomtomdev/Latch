import Testing
import Foundation
import LatchDomain
@testable import LatchData

struct ZombieDiagnosticRunnerTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func runner(
        stderr: String = "", exitCode: Int32 = 0
    ) -> (ZombieDiagnosticRunner, RecordingCommandRunner) {
        let command = RecordingCommandRunner(
            result: CommandResult(stdout: "", stderr: stderr, exitCode: exitCode)
        )
        return (ZombieDiagnosticRunner(commandRunner: command), command)
    }

    private let target = Target(
        id: "4242", kind: .localMac, pid: 4242,
        executablePath: "/Applications/Leaky.app/Contents/MacOS/Leaky", displayName: "Leaky"
    )

    // The hard constraint from SPEC §1: NSZombieEnabled is a launch-time env var, so zombies
    // cannot be detected on a running process — the runner must relaunch. (PLAN slice 7)
    @Test func requiresRelaunch_isTrueForZombies() {
        let (zombies, _) = runner()
        #expect(zombies.requiresRelaunch)
        #expect(zombies.kind == .zombies)
    }

    // The runner relaunches the target's executable with NSZombieEnabled=YES via /usr/bin/env
    // (CommandRunner has no env channel; env is the sanctioned launch-time injection). The exact
    // command is pinned so a regression is caught here. (SPEC §1, §3.2; PLAN slice 7)
    @Test func run_relaunchesExecutableWithNSZombieEnabled() async throws {
        let (zombies, command) = runner(stderr: try fixture("zombie-none"), exitCode: 0)

        _ = try await zombies.run(target, options: DiagnosticOptions())

        #expect(command.executablePath == "/usr/bin/env")
        #expect(command.arguments == [
            "NSZombieEnabled=YES", "/Applications/Leaky.app/Contents/MacOS/Leaky",
        ])
    }

    // A relaunch that messaged a deallocated instance: the runtime's stderr diagnostic parses
    // into a finding naming the method that was sent to the zombie. No backtrace is present —
    // MallocStackLogging does not add one to the stderr line. (SPEC §1, §3.3; PLAN slice 7)
    @Test func run_parsesZombieMessageIntoFinding() async throws {
        let (zombies, _) = runner(stderr: try fixture("zombie-detected"), exitCode: 133)

        let result = try await zombies.run(target, options: DiagnosticOptions())

        #expect(result.kind == .zombies)
        #expect(result.hasFindings)
        #expect(result.findings.count == 1)
        let finding = try #require(result.findings.first)
        #expect(finding.title == "-[LatchLeaky doWork]")
        #expect(finding.instanceCount == 1)
        #expect(finding.backtrace.isEmpty)
        #expect(!result.hasBacktraces)
    }

    // A clean relaunch (proper object lifecycle, exit 0) reports no zombies — distinct from a
    // detection, and never a tool failure. Absence isn't proof, so the summary is worded as
    // "observed", not "no zombies exist". (SPEC §1)
    @Test func run_reportsNoZombies_whenStderrHasNoZombieMessage() async throws {
        let (zombies, _) = runner(stderr: try fixture("zombie-none"), exitCode: 0)

        let result = try await zombies.run(target, options: DiagnosticOptions())

        #expect(!result.hasFindings)
        #expect(result.summary.localizedCaseInsensitiveContains("no zombie"))
    }

    // When /usr/bin/env cannot exec the binary (exit 127, "No such file or directory") the
    // relaunch failed — surfaced honestly, not parsed as "no zombies". (SPEC §1)
    @Test func run_throwsToolFailed_whenRelaunchCannotExec() async throws {
        let (zombies, _) = runner(stderr: try fixture("zombie-launch-failed"), exitCode: 127)

        await #expect(throws: DiagnosticError.self) {
            try await zombies.run(target, options: DiagnosticOptions())
        }
    }

    // A target with no executable path cannot be relaunched — reported distinctly, never as an
    // empty/clean run. (PLAN slice 7)
    @Test func run_throwsTargetHasNoExecutablePath_whenPathMissing() async throws {
        let (zombies, _) = runner()
        let pathless = Target(id: "x", kind: .localMac, pid: 7, displayName: "no path")

        await #expect(throws: DiagnosticError.targetHasNoExecutablePath) {
            try await zombies.run(pathless, options: DiagnosticOptions())
        }
    }
}
