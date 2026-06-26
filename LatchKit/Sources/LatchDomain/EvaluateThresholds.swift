// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Use case: given a live window of samples and the active thresholds, decide which
/// signals are currently in breach. Pure and deterministic — the polling loop feeds it
/// the ring buffer each tick and renders the returned alerts. (SPEC §3.3)
///
/// Two breach shapes, one per signal's nature:
/// - **Sustained** (CPU spike): the trailing `window` samples must *all* breach.
/// - **Rising trend** (memory leak): the footprint's slope over the `window`, projected
///   to MB/min, must breach — this is the live leak *hint*, not a leak proof. (SPEC §1)
public struct EvaluateThresholds: Sendable {
    public init() {}

    public func callAsFunction(samples: [MetricSample], thresholds: [Threshold]) -> [Alert] {
        thresholds.compactMap { alert(for: $0, over: samples) }
    }

    private func alert(for threshold: Threshold, over samples: [MetricSample]) -> Alert? {
        switch threshold.signal {
        case .memoryLeak: risingTrendAlert(threshold, samples)
        case .cpuSpike: sustainedAlert(threshold, samples, measuring: \.cpuPercent)
        case .networkIO: sustainedAlert(threshold, samples, measuring: \.networkMegabytesPerSecond)
        case .battery: sustainedAlert(threshold, samples, measuring: \.energyWatts)
        default: nil // no live indicator yet — added with each signal's slice. (SPEC §1)
        }
    }

    /// Fires when *every* sample in the trailing window breaches `threshold` on the value
    /// at `measure` — the "sustained" breach shape shared by CPU spikes and network I/O.
    private func sustainedAlert(
        _ threshold: Threshold,
        _ samples: [MetricSample],
        measuring measure: (MetricSample) -> Double
    ) -> Alert? {
        guard let window = trailingWindow(samples, threshold.window) else { return nil }
        let allBreach = window.samples.allSatisfy {
            threshold.comparator.matches(measure($0), threshold.value)
        }
        guard allBreach else { return nil }
        return Alert(signal: threshold.signal, severity: .warning, sample: window.latest)
    }

    private func risingTrendAlert(_ threshold: Threshold, _ samples: [MetricSample]) -> Alert? {
        guard let window = trailingWindow(samples, threshold.window) else { return nil }
        let footprints = window.samples.map(\.physFootprintMegabytes)
        let megabytesPerMinute = slopePerSample(footprints) * 60 // 1 Hz: 60 samples per minute.
        guard threshold.comparator.matches(megabytesPerMinute, threshold.value) else { return nil }
        return Alert(signal: threshold.signal, severity: .warning, sample: window.latest)
    }

    /// The trailing `count` samples plus their most recent member. `nil` when fewer than
    /// `count` exist — too little evidence to judge a sustained breach or a trend.
    private struct Window {
        let samples: [MetricSample]
        let latest: MetricSample
    }

    private func trailingWindow(_ samples: [MetricSample], _ count: Int) -> Window? {
        guard count > 0, samples.count >= count, let latest = samples.last else { return nil }
        return Window(samples: Array(samples.suffix(count)), latest: latest)
    }

    /// Least-squares slope of `values` against their sample index (0, 1, 2, …). Positive
    /// means a rising trend; noise around a flat baseline averages out near zero.
    private func slopePerSample(_ values: [Double]) -> Double {
        let n = Double(values.count)
        let meanX = (n - 1) / 2
        let meanY = values.reduce(0, +) / n
        var covariance = 0.0
        var varianceX = 0.0
        for (index, value) in values.enumerated() {
            let dx = Double(index) - meanX
            covariance += dx * (value - meanY)
            varianceX += dx * dx
        }
        guard varianceX > 0 else { return 0 }
        return covariance / varianceX
    }
}
