import Foundation
import LatchDomain

/// Detects over-released ("zombie") objects by **relaunching** the target under
/// `NSZombieEnabled`, behind the `CommandRunner` seam. Zombie detection is impossible on a
/// running process: `NSZombieEnabled` is an environment variable the Obj-C runtime reads at
/// launch, so the target must be started afresh under it — `requiresRelaunch` is `true` and
/// the UI must say so. (SPEC §1, §3.2; PLAN slice 7)
///
/// There is **no `Zombies` Instruments template/instrument** in current Xcode (verified on
/// macOS 26.2 / Xcode 16: absent from `xctrace list templates` and `list instruments`), so
/// this runner uses the underlying sanctioned mechanism directly rather than `xctrace`. The
/// env var is injected via `/usr/bin/env` (the `CommandRunner` has no env channel). When a
/// deallocated instance is messaged the runtime logs `*** -[Class selector]: message sent to
/// deallocated instance 0x…` to **stderr** and the process aborts (`SIGTRAP`, exit 133); the
/// abort is the expected outcome, not a tool failure. `MallocStackLogging` adds no backtrace
/// to that stderr line, so findings carry no stack — the retain/release history needs
/// Instruments. (SPEC §1, §7)
///
/// Bounding a relaunch that never crashes (a non-buggy target runs until the runner's process
/// infrastructure stops it) is a `ProcessCommandRunner` concern validated in the manual
/// integration smoke (SPEC §6); this slice TDDs the command + parse against captured fixtures.
public struct ZombieDiagnosticRunner: DiagnosticRunner {
    public let kind: DiagnosticKind = .zombies
    public let requiresRelaunch = true

    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }

    public func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult {
        guard let executablePath = target.executablePath, !executablePath.isEmpty else {
            throw DiagnosticError.targetHasNoExecutablePath
        }
        let result = try await commandRunner.run(
            "/usr/bin/env", arguments: ["NSZombieEnabled=YES", executablePath]
        )
        let report = Self.parse(result.stderr)
        guard report.hasFindings || !Self.isLaunchFailure(result.exitCode) else {
            throw DiagnosticError.toolFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return report
    }

    /// `/usr/bin/env` exits 127 when the executable is not found and 126 when it cannot be
    /// run — the "couldn't relaunch" cases. The target's own non-zero exit (or a zombie abort)
    /// is not a launcher failure.
    private static func isLaunchFailure(_ exitCode: Int32) -> Bool {
        exitCode == 126 || exitCode == 127
    }

    // MARK: - Parsing
    //
    // Regex literal is declared locally rather than as a static let: `Regex` is not
    // `Sendable`, so a shared static would be a Swift 6 concurrency error.

    /// Map a relaunch's stderr to a `DiagnosticResult`. Each `message sent to deallocated
    /// instance` line is a zombie messaging; identical method signatures are grouped into one
    /// finding carrying the instance count.
    static func parse(_ stderr: String) -> DiagnosticResult {
        let findings = groupedFindings(in: zombieSignatures(in: stderr))
        return DiagnosticResult(kind: .zombies, summary: summary(for: findings), findings: findings)
    }

    /// The method signature (e.g. `-[LatchLeaky doWork]`) of every zombie message, in order.
    private static func zombieSignatures(in stderr: String) -> [String] {
        let zombieLinePattern = /\*\*\* ([-+]\[[^\]]+\]): message sent to deallocated instance 0x[0-9a-fA-F]+/
        return stderr.matches(of: zombieLinePattern).map { String($0.1) }
    }

    /// One finding per distinct signature, its `instanceCount` the number of times that zombie
    /// was messaged. Order follows first appearance. Zombie findings carry no bytes or stack.
    private static func groupedFindings(in signatures: [String]) -> [Finding] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for signature in signatures {
            if counts[signature] == nil { order.append(signature) }
            counts[signature, default: 0] += 1
        }
        return order.map { signature in
            Finding(title: signature, byteCount: 0, instanceCount: counts[signature] ?? 1)
        }
    }

    private static func summary(for findings: [Finding]) -> String {
        guard !findings.isEmpty else { return "No zombie messages observed during the run." }
        let total = findings.reduce(0) { $0 + $1.instanceCount }
        let noun = total == 1 ? "zombie message" : "zombie messages"
        return "\(total) \(noun) detected — object messaged after deallocation."
    }
}
