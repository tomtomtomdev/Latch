import Foundation
import LatchDomain

/// Records a deep diagnostic trace via Instruments' CLI front-end (`xcrun xctrace record`),
/// behind the `CommandRunner` seam. Latch *summarizes and hands off* — it captures the
/// `.trace` bundle and returns its path so the user opens the full analysis in Instruments;
/// it does not re-implement the trace viewer. One recorder backs the two attach-based deep
/// runs Latch records: `.leaks` (`Leaks` template, slice 6) and `.hitches` (`Time Profiler`
/// template, slice 8). (SPEC §1, §3.2; PLAN slices 6, 8)
///
/// Template names verified on macOS 26.2 / Xcode 16 (`xctrace list templates` confirms both
/// `Leaks` and `Time Profiler`). The deep attach needs the `com.apple.security.cs.debugger`
/// entitlement to acquire the target's task port; without it `xctrace` exits non-zero ("Unable
/// to acquire required task port") and the runner throws `DiagnosticError.toolFailed` rather
/// than returning a hollow trace. (SPEC §1, §5, §7)
///
/// Parsing the exported trace (`xctrace export`) into `Finding`s is **deferred**: the export
/// XML schema is version-specific and cannot be captured/verified without the entitled app,
/// so this slice ships the verified record + `.trace` path only. Automated export parsing is
/// validated in the manual integration smoke (SPEC §6) before being relied upon. The quick
/// same-UID paths (`leaks`/`sample`) are the verifiable live findings. (PLAN slices 6, 8)
public struct XctraceDiagnosticRunner: DiagnosticRunner {
    public let kind: DiagnosticKind
    public let requiresRelaunch = false

    private let commandRunner: CommandRunner
    private let outputDirectory: String

    public init(commandRunner: CommandRunner, outputDirectory: String, kind: DiagnosticKind = .leaks) {
        self.commandRunner = commandRunner
        self.outputDirectory = outputDirectory
        self.kind = kind
    }

    public func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult {
        guard let pid = target.pid else { throw DiagnosticError.targetHasNoPID }
        guard let template = Self.template(for: kind), let slug = Self.slug(for: kind) else {
            throw DiagnosticError.toolFailed(exitCode: -1, message: "No xctrace template for \(kind).")
        }
        let tracePath = URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent("Latch-\(slug)-\(pid).trace").path
        let result = try await commandRunner.run("/usr/bin/xcrun", arguments: [
            "xctrace", "record", "--template", template,
            "--attach", "\(pid)",
            "--time-limit", "\(options.timeLimit.components.seconds)s",
            "--output", tracePath,
        ])
        guard result.exitCode == 0 else {
            throw DiagnosticError.toolFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return DiagnosticResult(
            kind: kind,
            summary: "Recorded a \(template) trace — open it in Instruments for the full analysis.",
            findings: [],
            tracePath: tracePath
        )
    }

    /// The Instruments template for a kind, or `nil` for kinds with no xctrace template
    /// (Zombies — handled by `ZombieDiagnosticRunner`, never recorded here). (SPEC §3.2)
    private static func template(for kind: DiagnosticKind) -> String? {
        switch kind {
        case .leaks: "Leaks"
        case .hitches: "Time Profiler"
        case .zombies: nil
        }
    }

    /// The `.trace` filename slug for a kind.
    private static func slug(for kind: DiagnosticKind) -> String? {
        switch kind {
        case .leaks: "leaks"
        case .hitches: "hitches"
        case .zombies: nil
        }
    }
}
