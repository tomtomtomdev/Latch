import Foundation
import LatchDomain

/// Quick hitch/hang look at a running same-UID process via `sample <pid>`, behind the
/// `CommandRunner` seam. This is Latch's **verified** same-UID sampling path (SPEC §1's
/// light deep-run end): `sample` suspends the target at a fixed interval, records every
/// thread's call stack, and works **without root** — unlike `spindump`, which "must be run
/// as root when sampling the live system" and is therefore gated (deferred, like
/// `powermetrics`). The deep `xctrace` Time Profiler attach hits the same debugger-entitlement
/// task-port wall as Leaks. (SPEC §1, §3.2; PLAN slice 8)
///
/// Command and call-tree shape verified on macOS 26.2 / Xcode 16 (`man sample`, live captures
/// in `Fixtures/`): exit 0 = sampled, 255 = process gone (thrown). The runner locates the
/// `com.apple.main-thread` block, reconstructs a stack series from its call tree — each
/// childless leaf becomes `count` copies of its root→leaf stack — and runs the Domain
/// `DetectHangs` heuristic. A wedged thread is a single non-branching spine whose leaf holds
/// all the samples; a busy thread branches into short-lived leaves, so high-count *internal*
/// frames never read as a stall. The stall verdict is an honest *hint* (sample counts are not
/// guaranteed consecutive, and a main thread parked in its run loop reads the same) — the
/// `.trace` is the ground truth. (SPEC §1, §7)
public struct SampleDiagnosticRunner: DiagnosticRunner {
    public let kind: DiagnosticKind = .hitches
    public let requiresRelaunch = false

    private let commandRunner: CommandRunner
    private let intervalMilliseconds: Int

    public init(commandRunner: CommandRunner, intervalMilliseconds: Int = 10) {
        self.commandRunner = commandRunner
        self.intervalMilliseconds = intervalMilliseconds
    }

    public func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult {
        guard let pid = target.pid else { throw DiagnosticError.targetHasNoPID }
        let seconds = options.timeLimit.components.seconds
        let result = try await commandRunner.run("/usr/bin/sample", arguments: [
            "\(pid)", "\(seconds)", "\(intervalMilliseconds)",
        ])
        guard result.exitCode == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw DiagnosticError.toolFailed(exitCode: result.exitCode, message: message)
        }
        return parse(result.stdout)
    }

    // MARK: - Parsing

    /// One parsed call-tree line: its indent `column` (deeper = larger), `sampleCount`, and
    /// `frame` text. The indent column is the offset of the leading count past the whitespace
    /// and the arbitrary tree-drawing connectors (`+ ! : |`), and so encodes call depth.
    private struct FrameNode {
        let column: Int
        let sampleCount: Int
        let frame: String
    }

    /// Map raw `sample` stdout to a `DiagnosticResult` by reconstructing the main thread's
    /// stack series and running the shared `DetectHangs` heuristic over it.
    private func parse(_ stdout: String) -> DiagnosticResult {
        let interval = Self.samplingInterval(in: stdout) ?? .milliseconds(intervalMilliseconds)
        let series = Self.mainThreadSeries(in: stdout)
        let hangs = DetectHangs(interval: interval)(series)
        return DiagnosticResult(
            kind: .hitches,
            summary: Self.summary(for: hangs),
            findings: hangs.map(Self.finding)
        )
    }

    /// The sampling interval from the header line `… every N milliseconds`.
    private static func samplingInterval(in stdout: String) -> Duration? {
        let pattern = /every (\d+) milliseconds/
        guard let match = stdout.firstMatch(of: pattern), let ms = Int(match.1) else { return nil }
        return .milliseconds(ms)
    }

    /// Reconstruct the main thread's stack series from its call tree: each childless leaf
    /// becomes `sampleCount` consecutive copies of its root→leaf stack (the honest "this stack
    /// held the thread for that many samples" representation), so `DetectHangs` sees one run
    /// per distinct wedged stack.
    private static func mainThreadSeries(in stdout: String) -> [StackSample] {
        let lines = stdout.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: { $0.contains("com.apple.main-thread") }),
              let headerColumn = parseFrameLine(lines[headerIndex])?.column else { return [] }

        let nodes = mainThreadNodes(in: lines, after: headerIndex, deeperThan: headerColumn)
        var series: [StackSample] = []
        var spine: [FrameNode] = []
        for (index, node) in nodes.enumerated() {
            while let last = spine.last, last.column >= node.column { spine.removeLast() }
            spine.append(node)
            let isLeaf = index + 1 >= nodes.count || nodes[index + 1].column <= node.column
            guard isLeaf else { continue }
            let stack = StackSample(frames: spine.map(\.frame))
            series.append(contentsOf: repeatElement(stack, count: node.sampleCount))
        }
        return series
    }

    /// The main thread's frame lines: those after its header that are deeper than it, up to
    /// the first non-frame line (blank / next thread / the `Total number in stack` section).
    private static func mainThreadNodes(
        in lines: [String], after headerIndex: Int, deeperThan headerColumn: Int
    ) -> [FrameNode] {
        var nodes: [FrameNode] = []
        for line in lines[(headerIndex + 1)...] {
            guard let node = parseFrameLine(line), node.column > headerColumn else { break }
            nodes.append(node)
        }
        return nodes
    }

    /// Parse one call-tree line into a `FrameNode`. Returns `nil` for any line without a
    /// leading count (blank lines, section headers).
    private static func parseFrameLine(_ line: String) -> FrameNode? {
        let connectorPrefix: Set<Character> = [" ", "+", "!", ":", "|"]
        let chars = Array(line)
        var index = 0
        while index < chars.count, connectorPrefix.contains(chars[index]) { index += 1 }
        let column = index
        var digits = ""
        while index < chars.count, chars[index].isNumber { digits.append(chars[index]); index += 1 }
        guard let count = Int(digits) else { return nil }
        let frame = String(chars[index...]).trimmingCharacters(in: .whitespaces)
        guard !frame.isEmpty else { return nil }
        return FrameNode(column: column, sampleCount: count, frame: frame)
    }

    private static func finding(for hang: Hang) -> Finding {
        Finding(
            title: symbol(in: hang.leaf),
            byteCount: 0,
            instanceCount: hang.sampleCount,
            backtrace: hang.stack
        )
    }

    /// The symbol name from a `sample` frame, e.g. `__semwait_signal` from
    /// `__semwait_signal  (in libsystem_kernel.dylib) + 8  [0x…]`.
    private static func symbol(in frame: String) -> String {
        guard let range = frame.range(of: "  (in ") else { return frame }
        return String(frame[..<range.lowerBound])
    }

    private static func summary(for hangs: [Hang]) -> String {
        guard let worst = hangs.max(by: { $0.duration < $1.duration }) else {
            return "No main-thread stall over the hang threshold during the sampling run."
        }
        let noun = hangs.count == 1 ? "stall" : "stalls"
        let longest = milliseconds(worst.duration)
        return "\(hangs.count) main-thread \(noun) — longest ~\(longest) ms in \(symbol(in: worst.leaf))."
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds) * 1000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
