// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Use case: scan a main-thread stack series sampled at a fixed `interval` and flag every
/// maximal run of *consecutive* identical stacks whose elapsed span exceeds `threshold` (the
/// §3.3 hang bar, 250 ms by default). Pure and deterministic — the slice's required heuristic
/// test drives it with a synthetic series, and the `sample`-backed runner feeds it a series
/// reconstructed from the tool's call tree.
///
/// A *consecutive* run, not total time: the same stack seen on and off across the run is the
/// thread doing repeated work, not one long hang. The breach is strictly greater than the
/// threshold, matching SPEC §3.3's "blocked > 250 ms". (SPEC §1, §3.3; PLAN slice 8)
public struct DetectHangs: Sendable {
    public let interval: Duration
    public let threshold: Duration

    public init(interval: Duration, threshold: Duration = .milliseconds(250)) {
        self.interval = interval
        self.threshold = threshold
    }

    public func callAsFunction(_ samples: [StackSample]) -> [Hang] {
        var hangs: [Hang] = []
        var runStart = samples.startIndex
        while runStart < samples.endIndex {
            let runEnd = endOfRun(in: samples, from: runStart)
            let count = runEnd - runStart
            let duration = interval * count
            if duration > threshold {
                hangs.append(Hang(stack: samples[runStart].frames, sampleCount: count, duration: duration))
            }
            runStart = runEnd
        }
        return hangs
    }

    /// The end index (exclusive) of the maximal run of samples equal to `samples[start]`.
    private func endOfRun(in samples: [StackSample], from start: Int) -> Int {
        var end = start + 1
        while end < samples.endIndex, samples[end] == samples[start] {
            end += 1
        }
        return end
    }
}
