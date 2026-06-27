import Testing
import Foundation
import LatchDomain
@testable import LatchData

struct XctraceDiagnosticRunnerTests {
    private func runner(
        exitCode: Int32 = 0, stderr: String = ""
    ) -> (XctraceDiagnosticRunner, RecordingCommandRunner) {
        let command = RecordingCommandRunner(
            result: CommandResult(stdout: "", stderr: stderr, exitCode: exitCode)
        )
        let xctrace = XctraceDiagnosticRunner(commandRunner: command, outputDirectory: "/tmp/latch-traces")
        return (xctrace, command)
    }

    private let target = Target(id: "4242", kind: .localMac, pid: 4242, displayName: "leaker")

    // Leaks attach live — the runner never requires a relaunch (unlike Zombies). (SPEC §1)
    @Test func requiresRelaunch_isFalseForLeaks() {
        let (xctrace, _) = runner()
        #expect(!xctrace.requiresRelaunch)
    }

    // The runner invokes exactly the verified record command (xcrun xctrace record, Leaks
    // template, attach by pid, bounded by the option's time limit, into a per-pid .trace), and
    // hands back that path so the user can open the full analysis in Instruments. (PLAN slice 6)
    @Test func run_recordsLeaksTraceWithTheVerifiedCommand() async throws {
        let (xctrace, command) = runner(exitCode: 0)

        let result = try await xctrace.run(target, options: DiagnosticOptions(timeLimit: .seconds(5)))

        #expect(command.executablePath == "/usr/bin/xcrun")
        #expect(command.arguments == [
            "xctrace", "record", "--template", "Leaks",
            "--attach", "4242",
            "--time-limit", "5s",
            "--output", "/tmp/latch-traces/Latch-leaks-4242.trace",
        ])
        #expect(result.tracePath == "/tmp/latch-traces/Latch-leaks-4242.trace")
        #expect(result.kind == .leaks)
        #expect(!result.hasFindings)
    }

    // The same recorder, constructed for hitches, records a Time Profiler trace (the verified
    // template for main-thread stalls) into a per-pid `.trace` and hands back its path. Export
    // parsing is deferred — the deep attach hits the same debugger-entitlement task-port wall
    // as Leaks. (SPEC §1; PLAN slice 8)
    @Test func run_recordsTimeProfilerTrace_forHitches() async throws {
        let command = RecordingCommandRunner(result: CommandResult(stdout: "", stderr: "", exitCode: 0))
        let xctrace = XctraceDiagnosticRunner(
            commandRunner: command, outputDirectory: "/tmp/latch-traces", kind: .hitches
        )

        let result = try await xctrace.run(target, options: DiagnosticOptions(timeLimit: .seconds(5)))

        #expect(xctrace.kind == .hitches)
        #expect(command.arguments == [
            "xctrace", "record", "--template", "Time Profiler",
            "--attach", "4242",
            "--time-limit", "5s",
            "--output", "/tmp/latch-traces/Latch-hitches-4242.trace",
        ])
        #expect(result.tracePath == "/tmp/latch-traces/Latch-hitches-4242.trace")
        #expect(result.kind == .hitches)
    }

    // iOS routing (PLAN slice 9): when the target lives on a device, the runner inserts
    // `--device <udid>` (the hardware UDID `xctrace` keys on, verified against `xctrace list
    // devices`) ahead of the attach so the recording happens on the device, not the host.
    // Local-Mac targets carry no `deviceUDID`, so the host path above stays `--device`-free.
    @Test func run_routesThroughDeviceUDID_forIOSDeviceTargets() async throws {
        let (xctrace, command) = runner(exitCode: 0)
        let iosTarget = Target(
            id: "ios-700", kind: .iOSDevice, pid: 700,
            displayName: "MyApp", deviceUDID: "00008030-000000000000002E"
        )

        let result = try await xctrace.run(iosTarget, options: DiagnosticOptions(timeLimit: .seconds(5)))

        #expect(command.arguments == [
            "xctrace", "record", "--template", "Leaks",
            "--device", "00008030-000000000000002E",
            "--attach", "700",
            "--time-limit", "5s",
            "--output", "/tmp/latch-traces/Latch-leaks-700.trace",
        ])
        #expect(result.tracePath == "/tmp/latch-traces/Latch-leaks-700.trace")
    }

    // The deep attach needs the debugger entitlement to acquire the task port; when it can't
    // (the real failure captured during development), the runner surfaces the tool's error
    // honestly rather than pretending the trace is valid. (SPEC §1)
    @Test func run_throwsToolFailed_whenAttachCannotAcquireTaskPort() async throws {
        let (xctrace, _) = runner(exitCode: 2, stderr: "Unable to acquire required task port")

        await #expect(throws: DiagnosticError.self) {
            try await xctrace.run(target, options: DiagnosticOptions(timeLimit: .seconds(5)))
        }
    }
}
