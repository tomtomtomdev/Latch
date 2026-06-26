// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// A tunable alerting rule for one signal: breach `value` under `comparator`, sustained
/// over a trailing `window` of samples, and an alert fires. `window` is a sample count
/// (the live loop polls at 1 Hz, so it doubles as seconds). Thresholds are *defaults,
/// not science* — they ship configurable and are tuned per target. (SPEC §3.3, §4)
public struct Threshold: Sendable, Equatable, Identifiable {
    public let signal: SignalKind
    public let comparator: Comparator
    public let value: Double
    public let window: Int

    public var id: SignalKind { signal }

    public init(signal: SignalKind, comparator: Comparator, value: Double, window: Int) {
        self.signal = signal
        self.comparator = comparator
        self.value = value
        self.window = window
    }
}

public extension Threshold {
    /// Starting-point thresholds for the signals with a live indicator today. The other
    /// signals (zombies, hitch, battery) gain defaults as their live or deep backing lands
    /// in later slices — no fake thresholds for capabilities that don't exist yet.
    /// (SPEC §1, §3.3)
    static let defaults: [Threshold] = [
        // CPU spike: > 80% of one core for > 3 s.
        Threshold(signal: .cpuSpike, comparator: .greaterThan, value: 80, window: 3),
        // Memory leak hint: footprint rising > 2 MB/min over a 5 min window (300 s @ 1 Hz).
        Threshold(signal: .memoryLeak, comparator: .greaterThan, value: 2, window: 300),
        // Network I/O: > 5 MB/s sustained over 5 s.
        Threshold(signal: .networkIO, comparator: .greaterThan, value: 5, window: 5),
        // Energy: estimated power draw > 5 W sustained over 5 s. A starting point, not
        // science — the rusage estimate's magnitude varies by hardware; tune per target.
        Threshold(signal: .battery, comparator: .greaterThan, value: 5, window: 5),
    ]
}
