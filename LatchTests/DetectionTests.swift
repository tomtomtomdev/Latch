import Testing
import LatchDomain
@testable import Latch

/// A `Detection` is the display model for one inbox card / diagnostic detail, built from either a
/// live threshold `Alert` or a deep-run `Finding`. The mapping is where honesty is enforced: a
/// live hint carries live provenance and **no** symbolicated stack, so it can never masquerade as
/// a deep finding; a deep run carries the finding's real stack. (SPEC §1, §8; PLAN slice 12)
struct DetectionTests {
    private let sample = MetricSample(
        cpuPercent: 92,
        physFootprintBytes: 600 * 1_048_576,
        residentBytes: 0,
        threadCount: 0,
        netInBytesPerSec: 12_000_000,
        netOutBytesPerSec: 0,
        energyWatts: 6
    )

    private func liveHint(_ signal: SignalKind, _ severity: AlertSeverity = .warning) -> Detection {
        Detection.liveHint(
            from: Alert(signal: signal, severity: severity, sample: sample), id: 1, sampleTick: 5
        )
    }

    // A live hint is provenance-tagged live, from its adapter, with no stack/call tree/trace —
    // it must never look like a symbolicated deep finding. (SPEC §8 honesty)
    @Test func liveHint_isLive_withNoSymbolicatedContent() {
        let detection = liveHint(.cpuSpike)
        #expect(detection.provenance.mode == .livePoll)
        #expect(detection.provenance.source == "proc_pid_rusage")
        #expect(detection.provenance.label == "Live hint · proc_pid_rusage")
        #expect(detection.stackTrace.isEmpty)
        #expect(detection.callTree.isEmpty)
        #expect(detection.tracePath == nil)
    }

    // Each live signal maps to its timeline lane (so a card's lane chip matches the lane it fired in).
    @Test func liveHint_mapsSignalToLane() {
        #expect(liveHint(.cpuSpike).lane == .cpu)
        #expect(liveHint(.memoryLeak).lane == .memory)
        #expect(liveHint(.networkIO).lane == .network)
        #expect(liveHint(.battery).lane == .energy)
    }

    // The network live hint comes from nettop, not the libproc rusage read.
    @Test func networkLiveHint_sourceIsNettop() {
        #expect(liveHint(.networkIO).provenance.source == "nettop")
    }

    // A live alert's severity carries through to the card.
    @Test func liveHint_carriesAlertSeverity() {
        #expect(liveHint(.cpuSpike, .warning).severity == .warning)
        #expect(liveHint(.battery, .critical).severity == .critical)
    }

    private func deepRun(_ kind: DiagnosticKind, backtrace: [String] = []) -> Detection {
        Detection.deepRun(
            from: Finding(title: "-[Foo bar]", byteCount: 0, instanceCount: 3, backtrace: backtrace),
            kind: kind, id: 7, tracePath: nil
        )
    }

    // A deep-run detection carries the finding's real stack trace and deep provenance.
    @Test func deepRun_carriesStackTraceAndProvenance() {
        let detection = deepRun(.zombies, backtrace: ["frame0", "frame1"])
        #expect(detection.stackTrace == ["frame0", "frame1"])
        #expect(detection.provenance.mode == .deepRun)
        #expect(detection.provenance.source == "NSZombieEnabled")
        #expect(detection.provenance.label == "Deep run · NSZombieEnabled")
    }

    // Zombies are use-after-free — the serious case → critical; other deep runs default to warning.
    @Test func deepRun_severityByKind() {
        #expect(deepRun(.zombies).severity == .critical)
        #expect(deepRun(.leaks).severity == .warning)
        #expect(deepRun(.hitches).severity == .warning)
    }

    // Deep-run kind maps to its lane; zombies has no live lane, so no lane chip.
    @Test func deepRun_mapsKindToLane() {
        #expect(deepRun(.leaks).lane == .memory)
        #expect(deepRun(.hitches).lane == .frame)
        #expect(deepRun(.zombies).lane == nil)
    }
}
