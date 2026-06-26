import Foundation
import LatchDomain

/// Records a deep Leaks trace via Instruments' CLI front-end (`xcrun xctrace record`),
/// behind the `CommandRunner` seam. Latch *summarizes and hands off* — it captures the
/// `.trace` bundle and returns its path so the user opens the full analysis in Instruments;
/// it does not re-implement the trace viewer. (SPEC §1, §3.2; PLAN slice 6)
///
/// Command shape verified on macOS 26.2 / Xcode 16 (`xctrace list templates` confirms the
/// `Leaks` template; the record command ran and parsed its flags). The deep attach needs the
/// `com.apple.security.cs.debugger` entitlement to acquire the target's task port; without it
/// `xctrace` exits non-zero ("Unable to acquire required task port") and the runner throws
/// `DiagnosticError.toolFailed` rather than returning a hollow trace. (SPEC §1, §5, §7)
///
/// Parsing the exported trace (`xctrace export`) into `Finding`s is **deferred**: the export
/// XML schema is version-specific and cannot be captured/verified without the entitled app,
/// so this slice ships the verified record + `.trace` path only. Automated export parsing is
/// validated in the manual integration smoke (SPEC §6) before being relied upon. (PLAN slice 6)
public struct XctraceDiagnosticRunner: DiagnosticRunner {
    public let kind: DiagnosticKind = .leaks
    public let requiresRelaunch = false

    private let commandRunner: CommandRunner
    private let outputDirectory: String

    public init(commandRunner: CommandRunner, outputDirectory: String) {
        self.commandRunner = commandRunner
        self.outputDirectory = outputDirectory
    }

    public func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult {
        guard let pid = target.pid else { throw DiagnosticError.targetHasNoPID }
        let tracePath = URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent("Latch-leaks-\(pid).trace").path
        let result = try await commandRunner.run("/usr/bin/xcrun", arguments: [
            "xctrace", "record", "--template", "Leaks",
            "--attach", "\(pid)",
            "--time-limit", "\(options.timeLimit.components.seconds)s",
            "--output", tracePath,
        ])
        guard result.exitCode == 0 else {
            throw DiagnosticError.toolFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return DiagnosticResult(
            kind: .leaks,
            summary: "Recorded a Leaks trace — open it in Instruments for the full analysis.",
            findings: [],
            tracePath: tracePath
        )
    }
}
