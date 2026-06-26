import SwiftUI
import LatchDomain

/// The live monitoring status of one signal, for the dashboard status pills. Honest
/// about reach: only the signals with a live indicator today (CPU, memory) report
/// `ok`/`alerting`; the rest are `unavailable` until their slice lands. (SPEC §1, §3.3)
enum SignalStatus {
    case ok
    case alerting
    case unavailable

    var color: Color {
        switch self {
        case .ok: .green
        case .alerting: .red
        case .unavailable: .secondary
        }
    }

    var label: String {
        switch self {
        case .ok: "OK"
        case .alerting: "Alert"
        case .unavailable: "—"
        }
    }
}

extension SignalKind {
    /// Short display title for the status pills.
    var title: String {
        switch self {
        case .memoryLeak: "Memory"
        case .zombies: "Zombies"
        case .hitch: "Hitches"
        case .cpuSpike: "CPU"
        case .networkIO: "Network"
        case .battery: "Energy"
        }
    }

    /// Signals Latch can monitor from the live polling loop today. Network joined them via
    /// `nettop` throughput (PLAN slice 4). The others need a deep diagnostic run (zombies,
    /// hitches) or a source from a later slice (energy) and stay `unavailable` until then —
    /// never faked. (SPEC §1)
    var hasLiveIndicator: Bool {
        self == .cpuSpike || self == .memoryLeak || self == .networkIO
    }
}
