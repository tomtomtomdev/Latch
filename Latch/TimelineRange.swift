import Foundation

/// The visible span of the live timeline, mapped to a count of 1 Hz samples in the per-target
/// ring buffer. The three spans mirror the handoff's `30s · 1m · 5m` segmented control; all are
/// well within the retention cap (SPEC §4), so a range only *trims* what is shown. (PLAN slice 11)
nonisolated enum TimelineRange: String, CaseIterable, Identifiable {
    case thirtySeconds
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }

    /// Toolbar label for the segmented control.
    var label: String {
        switch self {
        case .thirtySeconds: "30s"
        case .oneMinute: "1m"
        case .fiveMinutes: "5m"
        }
    }

    /// Number of trailing samples this span shows, at the slice-2 ~1 Hz cadence.
    var sampleCount: Int {
        switch self {
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }
}
