import LatchDomain

/// The right-panel inbox feed: an ordered, capped, provenance-tagged log of detections merging
/// live threshold alerts and deep-run findings. A pure value type — its ordering, capping, and
/// edge-triggering are unit-testable without the poll pipeline. Newest detection first. (PLAN slice 12)
nonisolated struct DetectionLog {
    private(set) var detections: [Detection] = []
    private var sequence = 0
    /// Signals currently in the active alert set — so a *sustained* alert logs one card per firing
    /// (edge-triggered), not one every tick, and a cleared-then-refired signal logs a fresh card.
    private var activeSignals: Set<SignalKind> = []
    let cap: Int

    /// `cap` defaults to the handoff's ~16-card feed.
    init(cap: Int = 16) {
        self.cap = cap
    }

    /// Reconcile the live alert set: log a live-hint card for each signal that just became active,
    /// and forget signals that cleared so a later re-fire logs again. (SPEC §3.3; PLAN slice 12)
    mutating func syncAlerts(_ alerts: [Alert], sampleTick: Int) {
        for alert in alerts where !activeSignals.contains(alert.signal) {
            prepend(.liveHint(from: alert, id: nextID(), sampleTick: sampleTick))
        }
        activeSignals = Set(alerts.map(\.signal))
    }

    /// Log a completed deep run: one card per finding, deep-run provenance. A clean run (no
    /// findings) logs nothing — the feed is a detection log, not a run log. (SPEC §1; PLAN slice 12)
    mutating func addDeepRun(_ result: DiagnosticResult) {
        for finding in result.findings {
            prepend(.deepRun(from: finding, kind: result.kind, id: nextID(), tracePath: result.tracePath))
        }
    }

    private mutating func prepend(_ detection: Detection) {
        detections.insert(detection, at: 0)
        if detections.count > cap {
            detections.removeLast(detections.count - cap)
        }
    }

    private mutating func nextID() -> Int {
        sequence += 1
        return sequence
    }
}
