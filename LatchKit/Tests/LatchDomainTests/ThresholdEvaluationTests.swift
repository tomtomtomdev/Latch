import Testing
import LatchDomain

struct ComparatorTests {
    @Test func matches_greaterThan() {
        #expect(Comparator.greaterThan.matches(81, 80))
        #expect(!Comparator.greaterThan.matches(80, 80))
    }

    @Test func matches_greaterThanOrEqual() {
        #expect(Comparator.greaterThanOrEqual.matches(80, 80))
        #expect(!Comparator.greaterThanOrEqual.matches(79, 80))
    }

    @Test func matches_lessThan() {
        #expect(Comparator.lessThan.matches(79, 80))
        #expect(!Comparator.lessThan.matches(80, 80))
    }

    @Test func matches_lessThanOrEqual() {
        #expect(Comparator.lessThanOrEqual.matches(80, 80))
        #expect(!Comparator.lessThanOrEqual.matches(81, 80))
    }
}

struct EvaluateThresholdsTests {
    private let evaluate = EvaluateThresholds()

    private func cpu(_ percent: Double) -> MetricSample {
        MetricSample(cpuPercent: percent, physFootprintBytes: 0, residentBytes: 0, threadCount: 1)
    }

    private func footprint(_ megabytes: Double) -> MetricSample {
        MetricSample(
            cpuPercent: 0,
            physFootprintBytes: UInt64(megabytes * 1_048_576),
            residentBytes: 0,
            threadCount: 1
        )
    }

    private func network(megabytesPerSecond: Double) -> MetricSample {
        MetricSample(cpuPercent: 0, physFootprintBytes: 0, residentBytes: 0, threadCount: 1)
            .withNetwork(NetworkRate(inBytesPerSec: megabytesPerSecond * 1_000_000, outBytesPerSec: 0))
    }

    private let cpuThreshold = Threshold(signal: .cpuSpike, comparator: .greaterThan, value: 80, window: 3)
    private let leakThreshold = Threshold(signal: .memoryLeak, comparator: .greaterThan, value: 2, window: 6)
    private let networkThreshold = Threshold(signal: .networkIO, comparator: .greaterThan, value: 5, window: 3)

    // CPU spike fires only when the breach is sustained across the whole window. (SPEC §3.3)
    @Test func cpuSpike_firesWhenSustainedOverWindow() {
        let samples = [cpu(90), cpu(90), cpu(90)]

        let alerts = evaluate(samples: samples, thresholds: [cpuThreshold])

        #expect(alerts.map(\.signal) == [.cpuSpike])
    }

    // A single dip inside the window means the spike was not sustained — no alert.
    @Test func cpuSpike_doesNotFireWhenNotSustained() {
        let samples = [cpu(90), cpu(50), cpu(90)]

        let alerts = evaluate(samples: samples, thresholds: [cpuThreshold])

        #expect(alerts.isEmpty)
    }

    // Only the trailing `window` samples matter — an old low reading is ignored.
    @Test func cpuSpike_considersOnlyTrailingWindow() {
        let samples = [cpu(10), cpu(90), cpu(90), cpu(90)]

        let alerts = evaluate(samples: samples, thresholds: [cpuThreshold])

        #expect(alerts.map(\.signal) == [.cpuSpike])
    }

    // Fewer than `window` samples is not enough evidence to fire.
    @Test func cpuSpike_needsFullWindow() {
        let samples = [cpu(90), cpu(90)]

        let alerts = evaluate(samples: samples, thresholds: [cpuThreshold])

        #expect(alerts.isEmpty)
    }

    // The leak hint fires on a steadily rising footprint (a real upward trend). (SPEC §3.3)
    @Test func memoryLeak_firesOnRisingSeries() {
        let samples = [100, 101, 102, 103, 104, 105].map { footprint(Double($0)) }

        let alerts = evaluate(samples: samples, thresholds: [leakThreshold])

        #expect(alerts.map(\.signal) == [.memoryLeak])
    }

    // Noise around a flat baseline has no trend — the rise detector must not fire on it.
    @Test func memoryLeak_ignoresNoisyFlatSeries() {
        let samples = [100, 101, 99, 100, 101, 99].map { footprint(Double($0)) }

        let alerts = evaluate(samples: samples, thresholds: [leakThreshold])

        #expect(alerts.isEmpty)
    }

    // Network I/O fires only when throughput stays above the limit across the whole
    // window — a sustained breach, like a CPU spike. (SPEC §3.3)
    @Test func networkIO_firesWhenSustainedOverWindow() {
        let samples = [network(megabytesPerSecond: 6), network(megabytesPerSecond: 7), network(megabytesPerSecond: 6)]

        let alerts = evaluate(samples: samples, thresholds: [networkThreshold])

        #expect(alerts.map(\.signal) == [.networkIO])
    }

    // A single drop below the limit inside the window means the spike was not sustained.
    @Test func networkIO_doesNotFireOnABurst() {
        let samples = [network(megabytesPerSecond: 6), network(megabytesPerSecond: 1), network(megabytesPerSecond: 6)]

        let alerts = evaluate(samples: samples, thresholds: [networkThreshold])

        #expect(alerts.isEmpty)
    }

    // Defaults exist for every signal that has a live indicator in this slice. (SPEC §3.3)
    @Test func defaults_coverLiveSignals() {
        let signals = Set(Threshold.defaults.map(\.signal))

        #expect(signals.contains(.cpuSpike))
        #expect(signals.contains(.memoryLeak))
        #expect(signals.contains(.networkIO))
    }
}
