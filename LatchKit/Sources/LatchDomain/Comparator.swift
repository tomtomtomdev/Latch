// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// How a threshold compares a measured value against its configured limit. Pure
/// arithmetic, so threshold logic stays deterministic and testable. (SPEC §4)
public enum Comparator: String, Sendable, CaseIterable {
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual

    /// True when `measured` breaches `limit` under this comparator.
    public func matches(_ measured: Double, _ limit: Double) -> Bool {
        switch self {
        case .greaterThan: measured > limit
        case .greaterThanOrEqual: measured >= limit
        case .lessThan: measured < limit
        case .lessThanOrEqual: measured <= limit
        }
    }
}
