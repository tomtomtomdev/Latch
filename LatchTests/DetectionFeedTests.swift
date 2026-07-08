import Testing
import LatchDomain
@testable import Latch

/// The detection feed merges live threshold alerts and deep-run findings into one ordered,
/// capped, provenance-tagged log — the right-panel inbox. `DetectionLog` is a pure value type,
/// so its ordering/capping/edge-triggering are testable without the poll pipeline. (PLAN slice 12)
struct DetectionFeedTests {
    private let sample = MetricSample(
        cpuPercent: 90, physFootprintBytes: 0, residentBytes: 0, threadCount: 0
    )

    private func alert(_ signal: SignalKind, _ severity: AlertSeverity = .warning) -> Alert {
        Alert(signal: signal, severity: severity, sample: sample)
    }

    // Cards appear newest-first: the most recently fired detection sits at the top of the feed.
    @Test func feed_ordersNewestFirst() {
        var log = DetectionLog()
        log.syncAlerts([alert(.cpuSpike)], sampleTick: 1)
        log.syncAlerts([alert(.cpuSpike), alert(.networkIO)], sampleTick: 2)

        #expect(log.detections.map(\.signal) == [.networkIO, .cpuSpike])
    }

    // The feed is capped; once full, the oldest cards fall off. (PLAN slice 12)
    @Test func feed_capsAtLimit() {
        var log = DetectionLog(cap: 2)
        for _ in 0..<3 {
            log.syncAlerts([alert(.cpuSpike)], sampleTick: 0)   // fire
            log.syncAlerts([], sampleTick: 0)                   // clear, so the next fire logs again
        }

        #expect(log.detections.count == 2)
    }

    // A sustained alert logs one card per firing (edge-triggered), not one every tick; a cleared
    // signal that re-fires logs a fresh card.
    @Test func syncAlerts_edgeTriggered_onePerFiring() {
        var log = DetectionLog()
        log.syncAlerts([alert(.cpuSpike)], sampleTick: 1)
        log.syncAlerts([alert(.cpuSpike)], sampleTick: 2)   // still active — no new card
        #expect(log.detections.count == 1)

        log.syncAlerts([], sampleTick: 3)                   // cleared
        log.syncAlerts([alert(.cpuSpike)], sampleTick: 4)   // re-fired — new card
        #expect(log.detections.count == 2)
    }

    // A deep run logs one card per finding, tagged with deep-run provenance and its adapter.
    @Test func addDeepRun_logsFindingsWithDeepProvenance() {
        var log = DetectionLog()
        let result = DiagnosticResult(kind: .leaks, summary: "2 leaks", findings: [
            Finding(title: "A", byteCount: 16, instanceCount: 1),
            Finding(title: "B", byteCount: 32, instanceCount: 2),
        ])

        log.addDeepRun(result)

        #expect(log.detections.count == 2)
        #expect(log.detections.allSatisfy { $0.provenance.mode == .deepRun })
        #expect(log.detections.allSatisfy { $0.provenance.source == "leaks" })
    }

    // A clean deep run (no findings) logs nothing — the feed is a detection log, not a run log.
    @Test func addDeepRun_cleanRun_logsNothing() {
        var log = DetectionLog()
        log.addDeepRun(DiagnosticResult(kind: .leaks, summary: "0 leaks", findings: []))
        #expect(log.detections.isEmpty)
    }
}
