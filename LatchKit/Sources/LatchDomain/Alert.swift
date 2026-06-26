// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// How loud an alert is. Threshold breaches are warnings today; `critical` is reserved
/// for tiered signals (e.g. the energy "high" tier in a later slice). (SPEC §4)
public enum AlertSeverity: String, Sendable {
    case warning
    case critical
}

/// A fired alert: a signal breached its threshold, captured against the offending
/// sample. The breach is recomputed from the live window each tick, so there is one
/// active alert per signal at a time. The wall-clock `firedAt` and persistence are added
/// when sessions are stored (SPEC §4, slice 10) — kept out here to keep the Domain
/// evaluation pure and deterministic. (SPEC §4)
public struct Alert: Sendable, Equatable, Identifiable {
    public let signal: SignalKind
    public let severity: AlertSeverity
    public let sample: MetricSample

    public var id: SignalKind { signal }

    public init(signal: SignalKind, severity: AlertSeverity, sample: MetricSample) {
        self.signal = signal
        self.severity = severity
        self.sample = sample
    }
}
