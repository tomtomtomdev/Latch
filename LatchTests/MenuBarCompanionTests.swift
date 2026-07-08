import Testing
import LatchDomain
@testable import Latch

/// The menu-bar companion (SPEC §8; PLAN slice 13) is a glanceable dropdown over *all* attached
/// targets: per-target health line + issue count, the recent detections across targets, and
/// `Pause all` / `Resume all`. The state it binds to lives on `MainWindowModel` (fleet-wide) and
/// `VitalsModel` (per-target); both are testable with fakes, no `NSStatusItem` required.
@MainActor
struct MenuBarCompanionTests {
    private let target = Target(id: "1", kind: .localMac, pid: 1, displayName: "t")

    private func idleStream(id: String) -> VitalsModel {
        VitalsModel(
            source: FakeMetricsSource(readings: []),
            target: Target(id: id, kind: .localMac, pid: 1, displayName: id),
            pid: 1
        )
    }

    private func reading(cpu: UInt64, wall: UInt64) -> VitalsReading {
        VitalsReading(
            cpuTimeNanos: cpu, physFootprintBytes: 0, residentBytes: 0,
            threadCount: 1, wallClockNanos: wall
        )
    }

    /// Two readings a second apart with equal CPU + wall deltas derive a 100%-of-one-core sample —
    /// enough to breach a 50% CPU threshold and fire one live-hint detection.
    private func breachingStream() -> VitalsModel {
        let cpu = Threshold(signal: .cpuSpike, comparator: .greaterThan, value: 50, window: 1)
        return VitalsModel(
            source: FakeMetricsSource(readings: [reading(cpu: 0, wall: 0),
                                                 reading(cpu: 1_000_000_000, wall: 1_000_000_000)]),
            target: target, pid: 1, thresholds: [cpu]
        )
    }

    // MARK: - Fleet-wide pause/resume

    // "Pause all" freezes every attached stream's poller; "Resume all" un-freezes them.
    @Test func pauseAll_resumeAll_toggleEveryStream() {
        let model = MainWindowModel(streams: [idleStream(id: "A"), idleStream(id: "B")])
        #expect(model.allPaused == false)

        model.pauseAll()
        let allFrozen = model.streams.allSatisfy(\.isPaused)
        #expect(allFrozen)
        #expect(model.allPaused)

        model.resumeAll()
        let noneFrozen = model.streams.allSatisfy { !$0.isPaused }
        #expect(noneFrozen)
        #expect(model.allPaused == false)
    }

    // With nothing attached the fleet is not "all paused" — there is nothing to pause.
    @Test func allPaused_falseWhenNothingAttached() {
        #expect(MainWindowModel().allPaused == false)
    }

    // MARK: - Recent detections across targets

    // A brand-new fleet has no recent detections — the dropdown shows none.
    @Test func recentDetections_emptyByDefault() {
        #expect(MainWindowModel(streams: [idleStream(id: "A")]).recentDetections.isEmpty)
    }

    // Recent detections reflect an attached stream's slice-12 feed.
    @Test func recentDetections_reflectStreamFeed() async {
        let stream = breachingStream()
        await stream.poll()   // baseline
        await stream.poll()   // 100% sample → CPU breach → one live-hint detection
        let model = MainWindowModel(streams: [stream])

        #expect(model.recentDetections.contains { $0.signal == .cpuSpike })
    }

    // The recent list is capped at three — the dropdown is a glance, not the full inbox.
    @Test func recentDetections_cappedAtThree() async {
        let findings = (0..<5).map { Finding(title: "leak \($0)", byteCount: 16, instanceCount: 1) }
        let stream = VitalsModel(
            source: FakeMetricsSource(readings: []),
            leakChecker: FakeDiagnosticRunner(
                result: DiagnosticResult(kind: .leaks, summary: "5 leaks", findings: findings)
            ),
            target: target, pid: 1
        )
        await stream.checkLeaks()
        #expect(stream.detections.count == 5)

        let model = MainWindowModel(streams: [stream])
        #expect(model.recentDetections.count == 3)
    }

    // MARK: - Monitoring summary

    // The header pluralizes the attached-target count honestly.
    @Test func monitoringSummary_pluralizesCount() {
        #expect(MainWindowModel().monitoringSummary == "Monitoring 0 targets")
        #expect(MainWindowModel(streams: [idleStream(id: "A")]).monitoringSummary == "Monitoring 1 target")
        #expect(MainWindowModel(streams: [idleStream(id: "A"), idleStream(id: "B")])
            .monitoringSummary == "Monitoring 2 targets")
    }

    // MARK: - Per-target health line & issue count

    // A stream with no active alerts reads Healthy with a zero issue count.
    @Test func statusSummary_healthyWhenNoAlerts() {
        let stream = idleStream(id: "A")
        #expect(stream.health == .healthy)
        #expect(stream.issueCount == 0)
        #expect(stream.statusSummary == "Healthy")
    }

    // A stream with a live breach reports its health, count, and pluralized issue label.
    @Test func statusSummary_reflectsActiveAlerts() async {
        let stream = breachingStream()
        await stream.poll(); await stream.poll()

        #expect(stream.issueCount == 1)
        #expect(stream.health == .warning)
        #expect(stream.statusSummary == "1 issue")
    }

    // The compact vitals line summarizes the latest sample as CPU · memory · network.
    @Test func vitalsLine_summarizesLatestSample() async {
        let stream = breachingStream()
        await stream.poll(); await stream.poll()

        #expect(stream.vitalsLine.hasPrefix("CPU "))
        #expect(stream.vitalsLine.contains("MB"))
        #expect(stream.vitalsLine.contains("MB/s"))
    }

    // With no sample yet the vitals line is an honest placeholder, not a fabricated zero.
    @Test func vitalsLine_placeholderBeforeFirstSample() {
        #expect(idleStream(id: "A").vitalsLine == "—")
    }
}
