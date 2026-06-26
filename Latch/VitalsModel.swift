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
    private(set) var errorMessage: String?

    var latest: MetricSample? { samples.last }

    private let source: MetricsSource
    private let pid: Int32
    private let capacity: Int
    private var previousReading: VitalsReading?

    /// `capacity` defaults to one hour of 1 Hz samples — the retention cap from SPEC §4.
    init(source: MetricsSource, pid: Int32, capacity: Int = 3600) {
        self.source = source
        self.pid = pid
        self.capacity = capacity
    }

    /// One polling tick: read the target's vitals, derive a sample from the previous
    /// reading, and append it. The first tick only establishes a baseline (no delta yet).
    func poll() {
        do {
            let reading = try source.sample(pid: pid)
            if let previousReading {
                append(MetricSample.derive(from: previousReading, to: reading))
            }
            previousReading = reading
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func append(_ sample: MetricSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
