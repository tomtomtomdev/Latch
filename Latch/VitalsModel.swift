import Foundation
import LatchDomain

/// Presentation state for the live vitals dashboard of one latched target. Polls a
/// `MetricsSource` on a fixed cadence, derives a `MetricSample` from each consecutive
/// pair of readings, and keeps a bounded ring buffer of history for the charts. Depends
/// only on the Domain `MetricsSource` abstraction, so it is driven by a fake in tests.
/// (SPEC §3, §4; PLAN slice 2)
@MainActor
@Observable
final class VitalsModel {
    private(set) var samples: [MetricSample] = []
    private(set) var alerts: [Alert] = []
    private(set) var thresholds: [Threshold]
    private(set) var errorMessage: String?

    var latest: MetricSample? { samples.last }

    private let source: MetricsSource
    private let networkSource: NetworkSource?
    private let pid: Int32
    private let capacity: Int
    private let evaluateThresholds = EvaluateThresholds()
    private var previousReading: VitalsReading?
    private var previousNetworkReading: NetworkReading?

    /// `capacity` defaults to one hour of 1 Hz samples — the retention cap from SPEC §4.
    /// `networkSource` is optional: without it, samples carry a zero network rate.
    init(
        source: MetricsSource,
        networkSource: NetworkSource? = nil,
        pid: Int32,
        capacity: Int = 3600,
        thresholds: [Threshold] = Threshold.defaults
    ) {
        self.source = source
        self.networkSource = networkSource
        self.pid = pid
        self.capacity = capacity
        self.thresholds = thresholds
    }

    /// One polling tick: read the target's vitals, derive a sample from the previous
    /// reading, attach the network throughput, and append it. The first tick only
    /// establishes a baseline (no delta yet). The libproc read is authoritative for
    /// liveness — its failure surfaces as an error and stops the tick; the network read is
    /// best-effort and never clobbers that error.
    func poll() async {
        do {
            let reading = try source.sample(pid: pid)
            let networkRate = await sampleNetworkRate()
            if let previousReading {
                let sample = MetricSample.derive(from: previousReading, to: reading)
                append(sample.withNetwork(networkRate))
            }
            previousReading = reading
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Read the network counters and derive a rate from the previous reading. Best-effort:
    /// no source, or a transient `nettop` failure, yields a zero rate rather than failing
    /// the whole tick. (PLAN slice 4)
    private func sampleNetworkRate() async -> NetworkRate {
        guard let networkSource else { return .zero }
        do {
            let reading = try await networkSource.sample(pid: pid)
            defer { previousNetworkReading = reading }
            guard let previousNetworkReading else { return .zero }
            return NetworkRate.derive(from: previousNetworkReading, to: reading)
        } catch {
            return .zero
        }
    }

    /// Override one signal's threshold value (per-target tuning) and re-evaluate the
    /// current window so the UI reflects the change immediately. (SPEC §3.3)
    func updateThreshold(_ signal: SignalKind, value: Double) {
        thresholds = thresholds.map { threshold in
            guard threshold.signal == signal else { return threshold }
            return Threshold(
                signal: signal,
                comparator: threshold.comparator,
                value: value,
                window: threshold.window
            )
        }
        refreshAlerts()
    }

    private func append(_ sample: MetricSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        refreshAlerts()
    }

    private func refreshAlerts() {
        alerts = evaluateThresholds(samples: samples, thresholds: thresholds)
    }
}
