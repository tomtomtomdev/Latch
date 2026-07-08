import Testing
import LatchDomain
@testable import Latch

/// The stream feeds the right-panel inbox: live threshold breaches and deep-run findings both land
/// in one provenance-tagged feed, and a card/marker selection opens (and clears) its detail.
/// (PLAN slice 12)
@MainActor
struct VitalsModelDetectionTests {
    private let target = Target(id: "1", kind: .localMac, pid: 1, displayName: "t")

    private func reading(cpu: UInt64, wall: UInt64) -> VitalsReading {
        VitalsReading(
            cpuTimeNanos: cpu, physFootprintBytes: 0, residentBytes: 0,
            threadCount: 1, wallClockNanos: wall
        )
    }

    /// Two readings a second apart with equal CPU + wall deltas derive a 100%-of-one-core sample.
    private var busyReadings: [VitalsReading] {
        [reading(cpu: 0, wall: 0), reading(cpu: 1_000_000_000, wall: 1_000_000_000)]
    }

    private func breachingModel() -> VitalsModel {
        let cpu = Threshold(signal: .cpuSpike, comparator: .greaterThan, value: 50, window: 1)
        return VitalsModel(
            source: FakeMetricsSource(readings: busyReadings),
            target: target, pid: 1, thresholds: [cpu]
        )
    }

    // A brand-new stream has an empty feed — the inbox shows its "0 detections" empty state.
    @Test func detections_emptyByDefault() {
        let model = VitalsModel(source: FakeMetricsSource(readings: []), target: target, pid: 1)
        #expect(model.detections.isEmpty)
        #expect(model.selectedDetection == nil)
    }

    // A live threshold breach appends a live-hint detection to the feed. (PLAN slice 12)
    @Test func poll_thresholdBreach_appendsLiveHintDetection() async {
        let model = breachingModel()
        await model.poll()   // baseline reading
        await model.poll()   // derives the 100% sample → CPU breach

        #expect(model.detections.contains { $0.signal == .cpuSpike && $0.provenance.mode == .livePoll })
    }

    // Selecting a detection opens its detail; clearing returns to the inbox. (PLAN slice 12)
    @Test func selectDetection_opensDetail_clearReturnsToInbox() async throws {
        let model = breachingModel()
        await model.poll(); await model.poll()
        let detection = try #require(model.detections.first)

        model.selectDetection(detection.id)
        #expect(model.selectedDetection?.id == detection.id)

        model.clearSelectedDetection()
        #expect(model.selectedDetection == nil)
    }

    // A deep run with findings adds a deep-run detection to the same feed. (PLAN slice 12)
    @Test func checkLeaks_withFindings_addsDeepDetection() async {
        let result = DiagnosticResult(
            kind: .leaks, summary: "1 leak",
            findings: [Finding(title: "ROOT LEAK", byteCount: 16, instanceCount: 1)]
        )
        let model = VitalsModel(
            source: FakeMetricsSource(readings: []),
            leakChecker: FakeDiagnosticRunner(result: result), target: target, pid: 1
        )

        await model.checkLeaks()

        #expect(model.detections.contains { $0.provenance.mode == .deepRun && $0.title == "ROOT LEAK" })
    }

    // A live hint places a timeline marker within the visible window; deep runs place none.
    @Test func markerFraction_forLiveHintOnly() async throws {
        let model = breachingModel()
        await model.poll(); await model.poll()
        let live = try #require(model.detections.first { $0.provenance.mode == .livePoll })

        let fraction = try #require(model.markerFraction(for: live))
        #expect(fraction >= 0 && fraction <= 1)

        let deep = Detection.deepRun(
            from: Finding(title: "x", byteCount: 0, instanceCount: 1), kind: .leaks, id: 99, tracePath: nil
        )
        #expect(model.markerFraction(for: deep) == nil)
    }
}
