import LatchDomain

/// The at-a-glance health of an attached target, shown as the sidebar dot. It is a pure fold
/// over the target's active live alerts: any critical alert dominates, any alert at all is a
/// warning, otherwise healthy. Deep-run findings blend in with the detection inbox (slice 12);
/// today only live threshold alerts contribute. (Design handoff sidebar; PLAN slice 11)
nonisolated enum TargetHealth: String {
    case healthy
    case warning
    case critical

    /// Binding health color (SPEC §8 tokens).
    var colorHex: String {
        switch self {
        case .healthy: "#30D158"
        case .warning: "#FF9F0A"
        case .critical: "#FF453A"
        }
    }

    static func from(alerts: [Alert]) -> TargetHealth {
        if alerts.contains(where: { $0.severity == .critical }) { return .critical }
        return alerts.isEmpty ? .healthy : .warning
    }
}
