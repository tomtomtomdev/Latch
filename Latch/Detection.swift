import Foundation
import LatchDomain

/// How loud a detection reads in the inbox and on its timeline marker. Mirrors the SPEC §8
/// severity tokens (Critical / Warning / Info). Live alerts map from `AlertSeverity`; deep runs
/// derive it from their kind. (SPEC §8)
nonisolated enum DetectionSeverity: String {
    case critical
    case warning
    case info

    /// Binding severity color (SPEC §8 tokens).
    var colorHex: String {
        switch self {
        case .critical: "#FF453A"
        case .warning: "#FF9F0A"
        case .info: "#0A84FF"
        }
    }

    init(_ severity: AlertSeverity) {
        switch severity {
        case .warning: self = .warning
        case .critical: self = .critical
        }
    }
}

/// Where a detection came from and how it was obtained — the honest live-vs-deep distinction
/// SPEC §1/§8 forbids conflating. Reuses the Domain `SamplingMode`; `source` names the producing
/// adapter (e.g. `proc_pid_rusage`, `nettop`, `leaks`, `NSZombieEnabled`). (SPEC §1, §8)
nonisolated struct DetectionProvenance: Equatable {
    let mode: SamplingMode
    let source: String

    /// The label shown on the card / detail, e.g. `Live hint · proc_pid_rusage`.
    var label: String {
        switch mode {
        case .livePoll: "Live hint · \(source)"
        case .deepRun: "Deep run · \(source)"
        }
    }
}

/// One row of a diagnostic detail's call tree. `weightPercent`/`selfTime` are optional and stay
/// `nil` for the quick attach/sample runs (which yield frames, not weights) — the weighted tree
/// lives in the recorded `.trace`. Never a fabricated percentage. (SPEC §1, §8)
nonisolated struct CallTreeRow: Identifiable, Equatable {
    let id: Int
    let depth: Int
    let name: String
    let weightPercent: Double?
    let selfTime: String?
}

/// The display model for one detection: an inbox card and its diagnostic detail. Built from either
/// a live threshold `Alert` (a *hint*) or a deep-run `Finding` (measured). The two factories are
/// where honesty is enforced — a live hint carries no symbolicated stack/call tree, so it can never
/// masquerade as a deep finding. (SPEC §1, §8; PLAN slice 12)
nonisolated struct Detection: Identifiable, Equatable {
    /// Monotonic sequence id assigned by the feed; also gives the newest-first ordering.
    let id: Int
    let severity: DetectionSeverity
    let signal: SignalKind
    /// The timeline lane this detection belongs to (its card chip / marker color), or `nil` for a
    /// signal with no live lane (zombies).
    let lane: LaneKind?
    let title: String
    let subtitle: String
    let provenance: DetectionProvenance
    /// Cumulative sample index when a live hint fired, used to place its timeline marker. `nil` for
    /// deep runs — they are not a point on the live stream, so they appear only in the inbox.
    let sampleTick: Int?

    // Diagnostic-detail content.
    let metricLabel: String
    let metricValue: String
    let detail: String
    let callTree: [CallTreeRow]
    let stackTrace: [String]
    let suggestedFixes: [String]
    let tracePath: String?

    /// Build a live-hint card from a fired threshold alert. No stack, no call tree, no trace — a
    /// live hint is a threshold breach, not a symbolicated deep finding. (SPEC §8)
    static func liveHint(from alert: Alert, id: Int, sampleTick: Int) -> Detection {
        let signal = alert.signal
        return Detection(
            id: id,
            severity: DetectionSeverity(alert.severity),
            signal: signal,
            lane: signal.lane,
            title: signal.liveTitle,
            subtitle: signal.liveSubtitle(alert.sample),
            provenance: DetectionProvenance(mode: .livePoll, source: signal.liveSource),
            sampleTick: sampleTick,
            metricLabel: signal.metricLabel,
            metricValue: signal.liveMetricValue(alert.sample),
            detail: signal.liveDetail,
            callTree: [],
            stackTrace: [],
            suggestedFixes: signal.suggestedFixes,
            tracePath: nil
        )
    }

    /// Build a deep-run card from a diagnostic finding. Carries the finding's real backtrace (as
    /// both the stack trace and an indented call tree — no fabricated weights) and the `.trace`
    /// path when the run recorded one. (SPEC §1, §8)
    static func deepRun(from finding: Finding, kind: DiagnosticKind, id: Int, tracePath: String?) -> Detection {
        Detection(
            id: id,
            severity: kind.deepSeverity,
            signal: kind.signal,
            lane: kind.lane,
            title: finding.title,
            subtitle: kind.deepSubtitle(finding),
            provenance: DetectionProvenance(mode: .deepRun, source: kind.deepSource),
            sampleTick: nil,
            metricLabel: kind.metricLabel,
            metricValue: kind.deepMetricValue(finding),
            detail: kind.deepDetail,
            callTree: callTree(from: finding.backtrace),
            stackTrace: finding.backtrace,
            suggestedFixes: kind.suggestedFixes,
            tracePath: tracePath
        )
    }

    /// An indented call tree from a flat backtrace: depth by frame index, no weights (the quick
    /// runs don't produce them — the recorded `.trace` does). Empty when there is no backtrace.
    private static func callTree(from backtrace: [String]) -> [CallTreeRow] {
        backtrace.enumerated().map { index, frame in
            CallTreeRow(id: index, depth: index, name: frame, weightPercent: nil, selfTime: nil)
        }
    }
}

// MARK: - Signal → live-hint presentation

private extension SignalKind {
    /// The live lane a signal streams in, or `nil` for a signal with no live lane (zombies).
    nonisolated var lane: LaneKind? {
        switch self {
        case .cpuSpike: .cpu
        case .memoryLeak: .memory
        case .networkIO: .network
        case .battery: .energy
        case .hitch: .frame
        case .zombies: nil
        }
    }

    /// The adapter behind the live signal. Network comes from `nettop`; the rest ride the libproc
    /// rusage read.
    nonisolated var liveSource: String {
        self == .networkIO ? "nettop" : "proc_pid_rusage"
    }

    nonisolated var liveTitle: String {
        switch self {
        case .cpuSpike: "CPU spike"
        case .memoryLeak: "Possible memory leak"
        case .networkIO: "High network I/O"
        case .battery: "High energy use"
        case .hitch: "Main-thread hitch"
        case .zombies: "Zombie object"
        }
    }

    nonisolated var metricLabel: String {
        switch self {
        case .cpuSpike: "CPU"
        case .memoryLeak: "FOOTPRINT"
        case .networkIO: "THROUGHPUT"
        case .battery: "POWER"
        case .hitch: "FRAME"
        case .zombies: "OBJECT"
        }
    }

    nonisolated func liveMetricValue(_ sample: MetricSample) -> String {
        switch self {
        case .cpuSpike: String(format: "%.0f%%", sample.cpuPercent)
        case .memoryLeak: String(format: "%.0f MB", sample.physFootprintMegabytes)
        case .networkIO: String(format: "%.1f MB/s", sample.networkMegabytesPerSecond)
        case .battery: String(format: "%.1f W", sample.energyWatts)
        default: "—"
        }
    }

    nonisolated func liveSubtitle(_ sample: MetricSample) -> String {
        switch self {
        case .cpuSpike: String(format: "%.0f%% of one core, sustained", sample.cpuPercent)
        case .memoryLeak: String(format: "Footprint rising — %.1f MB", sample.physFootprintMegabytes)
        case .networkIO: String(format: "%.1f MB/s throughput, sustained", sample.networkMegabytesPerSecond)
        case .battery: String(format: "%.1f W estimated, sustained", sample.energyWatts)
        default: "Threshold breached"
        }
    }

    /// The honest note in the detail: this is a live threshold *hint*, and how to get the ground
    /// truth. Never claims a symbolicated origin. (SPEC §8)
    nonisolated var liveDetail: String {
        switch self {
        case .cpuSpike:
            "A live hint: CPU stayed over its threshold across the sustain window. Sampled cheaply "
                + "from rusage — run a Time Profiler deep run to see which stack is hot."
        case .memoryLeak:
            "A live hint: the memory footprint trend is rising. This is a heuristic, not proof — "
                + "run a Leak Check (or record a Leaks trace) to confirm and locate allocations."
        case .networkIO:
            "A live hint: throughput stayed over its threshold across the sustain window, from "
                + "nettop byte deltas. Latch summarizes rate, not payloads."
        case .battery:
            "A live hint: the energy estimate (rusage nanojoules → watts) stayed high. Measured "
                + "powermetrics energy is a separate on-demand upgrade and needs root."
        default:
            "A live threshold hint. Run the matching deep diagnostic for a symbolicated origin."
        }
    }

    nonisolated var suggestedFixes: [String] {
        switch self {
        case .cpuSpike:
            ["Profile with Time Profiler to find the hot stack.",
             "Move sustained work off the main thread."]
        case .memoryLeak:
            ["Run a Leak Check to confirm the trend is a real leak.",
             "Relaunch with MallocStackLogging=1 to capture allocation backtraces."]
        case .networkIO:
            ["Batch or throttle requests; avoid chatty polling.",
             "Check for an unbounded retry or download loop."]
        case .battery:
            ["Reduce sustained CPU/GPU and wake-ups.",
             "Measure with powermetrics (root) for the real energy impact."]
        default:
            ["Run the matching deep diagnostic to investigate."]
        }
    }
}

// MARK: - Diagnostic kind → deep-run presentation

private extension DiagnosticKind {
    nonisolated var signal: SignalKind {
        switch self {
        case .leaks: .memoryLeak
        case .hitches: .hitch
        case .zombies: .zombies
        }
    }

    nonisolated var lane: LaneKind? {
        switch self {
        case .leaks: .memory
        case .hitches: .frame
        case .zombies: nil
        }
    }

    /// The tool behind the deep run.
    nonisolated var deepSource: String {
        switch self {
        case .leaks: "leaks"
        case .hitches: "sample"
        case .zombies: "NSZombieEnabled"
        }
    }

    /// Zombies is a use-after-free — the serious case. Leaks/hitches default to warning.
    nonisolated var deepSeverity: DetectionSeverity {
        self == .zombies ? .critical : .warning
    }

    nonisolated var metricLabel: String {
        switch self {
        case .leaks: "LEAKED"
        case .hitches: "SAMPLES"
        case .zombies: "MESSAGES"
        }
    }

    nonisolated func deepMetricValue(_ finding: Finding) -> String {
        switch self {
        case .leaks: "\(finding.byteCount) bytes"
        case .hitches: "\(finding.instanceCount) samples"
        case .zombies: "\(finding.instanceCount)×"
        }
    }

    nonisolated func deepSubtitle(_ finding: Finding) -> String {
        switch self {
        case .leaks: "\(finding.instanceCount)× · \(finding.byteCount) bytes"
        case .hitches: "main thread wedged across \(finding.instanceCount) samples"
        case .zombies: "messaged \(finding.instanceCount)× after deallocation"
        }
    }

    nonisolated var deepDetail: String {
        switch self {
        case .leaks:
            "A deep run: leaks scanned the process's malloc zones. Backtraces need the target "
                + "launched with MallocStackLogging; the recorded .trace holds the full analysis."
        case .hitches:
            "A deep run: sample profiled the main thread and found a stack wedged past the hang "
                + "bar. An honest hint — an idle run-loop wait looks similar; the Time Profiler "
                + ".trace is ground truth."
        case .zombies:
            "A deep run: the target was relaunched under NSZombieEnabled and a message was sent to "
                + "a deallocated object. This is the fresh relaunch, not the live process."
        }
    }

    nonisolated var suggestedFixes: [String] {
        switch self {
        case .leaks:
            ["Break the retain cycle or release the owning reference.",
             "Relaunch with MallocStackLogging=1 to see where it was allocated."]
        case .hitches:
            ["Move the wedged work off the main thread.",
             "Open the Time Profiler .trace for the weighted call tree."]
        case .zombies:
            ["Fix the over-release / dangling reference to the object.",
             "Adopt ARC or a weak reference where the object outlives its owner."]
        }
    }
}
