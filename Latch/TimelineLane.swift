import Foundation
import LatchDomain

/// One lane of the live timeline (and the toolbar chip that mirrors it). A lane is a pure
/// *formatting* of the latest `MetricSample` — Latch never synthesizes a lane value.
///
/// Honesty (SPEC §1, §8 reconciliation): the four cheap signals — CPU, Memory, Network, and the
/// Energy **watts estimate** — are genuine live lanes. **Frame time** is *not* a cheap live
/// counter for an external attach; it is a sampling hint + on-demand Time Profiler run (slice 8),
/// so it is gated here: `isLive == false`, no live value, an em-dash readout. (PLAN slice 11)
nonisolated enum LaneKind: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case network
    case energy
    case frame

    var id: String { rawValue }

    /// Full lane name shown in the timeline gutter.
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .energy: "Energy"
        case .frame: "Frame time"
        }
    }

    /// Compact toolbar-chip label.
    var chipLabel: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "MEM"
        case .network: "NET"
        case .energy: "ENERGY"
        case .frame: "FRAME"
        }
    }

    /// Binding lane color (SPEC §8 tokens).
    var colorHex: String {
        switch self {
        case .cpu: "#FF9F0A"
        case .memory: "#BF5AF2"
        case .network: "#64D2FF"
        case .energy: "#30D158"
        case .frame: "#FF375F"
        }
    }

    /// Right-aligned scale hint in the gutter. The frame lane advertises its honest nature.
    var scaleHint: String {
        switch self {
        case .cpu: "0–100%"
        case .memory: "MB"
        case .network: "MB/s"
        case .energy: "W est."
        case .frame: "deep run"
        }
    }

    /// Whether this lane streams a genuine live value. Frame time does not (see type doc).
    var isLive: Bool { self != .frame }

    /// The live value for this lane from a sample, or `nil` for the gated frame lane.
    func value(from sample: MetricSample) -> Double? {
        switch self {
        case .cpu: sample.cpuPercent
        case .memory: sample.physFootprintMegabytes
        case .network: sample.networkMegabytesPerSecond
        case .energy: sample.energyWatts
        case .frame: nil
        }
    }

    /// The readout string for the chip/gutter: a unit-formatted live value, or an em-dash when
    /// there is no sample yet or the lane is gated (frame). Never a fabricated number.
    func formattedValue(from sample: MetricSample?) -> String {
        guard let sample, let value = value(from: sample) else { return "—" }
        switch self {
        case .cpu: return String(format: "%.0f%%", value)
        case .memory: return String(format: "%.0f", value)
        case .network: return String(format: "%.1f", value)
        case .energy: return String(format: "%.1f", value)
        case .frame: return "—"
        }
    }
}
