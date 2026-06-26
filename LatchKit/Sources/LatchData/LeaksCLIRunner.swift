import Foundation
import LatchDomain

/// Quick leak snapshot of a running same-UID process via `leaks <pid>`, behind the
/// `CommandRunner` seam. This is the fast attach path (SPEC §1): `leaks` scans the target's
/// malloc zones without the full task port, so it works where `xctrace`'s deep attach needs
/// the debugger entitlement. The `leaks`/text-parsing types stay inside this adapter.
/// (SPEC §3.2; PLAN slice 6)
///
/// Output and exit codes verified on macOS 26.2 / Xcode 16 (`man leaks`, live captures in
/// `Fixtures/`): exit 0 = no leaks, 1 = leaks found (both parsed), >1 = tool error (thrown).
/// Allocation backtraces appear only when the target launched with `MallocStackLogging`; the
/// parser reports their presence so the UI can surface that caveat. (SPEC §1, §7)
public struct LeaksCLIRunner: DiagnosticRunner {
    public let kind: DiagnosticKind = .leaks
    public let requiresRelaunch = false

    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }

    public func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult {
        guard let pid = target.pid else { throw DiagnosticError.targetHasNoPID }
        let result = try await commandRunner.run("/usr/bin/leaks", arguments: ["\(pid)"])
        guard result.exitCode <= 1 else {
            throw DiagnosticError.toolFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return Self.parse(result.stdout)
    }

    // MARK: - Parsing
    //
    // Regex literals are declared locally rather than as static lets: `Regex` is not
    // `Sendable`, so a shared static would be a Swift 6 concurrency error.

    /// Map raw `leaks` stdout to a `DiagnosticResult`. Findings come from the grouped
    /// `STACK OF …` blocks when backtraces are present, and from the flat `ROOT LEAK:` lines
    /// otherwise — so a leak is always visible, with or without `MallocStackLogging`.
    static func parse(_ stdout: String) -> DiagnosticResult {
        let findings = stdout.contains("STACK OF")
            ? backtracedFindings(in: stdout)
            : addressOnlyFindings(in: stdout)
        return DiagnosticResult(kind: .leaks, summary: summary(in: stdout), findings: findings)
    }

    private static func summary(in stdout: String) -> String {
        let summaryPattern = /(\d+) leaks? for (\d+) total leaked bytes/
        guard let match = stdout.firstMatch(of: summaryPattern) else { return "Leak check completed." }
        let count = match.1
        let noun = count == "1" ? "leak" : "leaks"
        return "\(count) \(noun) for \(match.2) total leaked bytes"
    }

    /// One finding per `STACK OF N INSTANCES OF '<title>':` block, carrying its instance
    /// count, allocation backtrace (the frames up to the `====` separator), and leaked bytes
    /// (the first byte figure after the separator — the group total).
    private static func backtracedFindings(in stdout: String) -> [Finding] {
        stdout.components(separatedBy: "STACK OF").dropFirst().compactMap(parseStackBlock)
    }

    private static func parseStackBlock(_ block: String) -> Finding? {
        let stackHeaderPattern = /(\d+) INSTANCES? OF '(.+?)':/
        let bytesPattern = /\((\d+) bytes\)/
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        guard let header = lines.first,
              let match = header.firstMatch(of: stackHeaderPattern) else { return nil }
        var frames: [String] = []
        var byteCount = 0
        var pastSeparator = false
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "====" {
                pastSeparator = true
            } else if !pastSeparator {
                if !trimmed.isEmpty { frames.append(trimmed) }
            } else if let bytes = trimmed.firstMatch(of: bytesPattern) {
                byteCount = Int(bytes.1) ?? 0
                break
            }
        }
        return Finding(
            title: String(match.2),
            byteCount: byteCount,
            instanceCount: Int(match.1) ?? 1,
            backtrace: frames
        )
    }

    /// One finding per individual `ROOT LEAK:` block line, used when no backtraces are
    /// present. The `<< TOTAL >>` summary line carries no `ROOT LEAK:` marker and is skipped.
    private static func addressOnlyFindings(in stdout: String) -> [Finding] {
        let rootLeakLinePattern = /(\d+) \((\d+) bytes\) ROOT LEAK: (.+)/
        return stdout.split(separator: "\n").compactMap { line in
            guard let match = line.firstMatch(of: rootLeakLinePattern) else { return nil }
            return Finding(
                title: stripTrailingSize(String(match.3)),
                byteCount: Int(match.2) ?? 0,
                instanceCount: Int(match.1) ?? 1
            )
        }
    }

    /// Drop the trailing ` [<size>]` block-size annotation from a leak title.
    private static func stripTrailingSize(_ title: String) -> String {
        guard let range = title.range(of: " [", options: .backwards) else { return title }
        return String(title[..<range.lowerBound])
    }
}
