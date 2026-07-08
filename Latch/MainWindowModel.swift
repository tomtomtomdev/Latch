import Foundation
import LatchDomain

/// Presentation state for the main window shell: the set of attached targets and which one's
/// live stream the center timeline shows. Each attached target owns its own `VitalsModel`
/// stream (its own ring buffer + alerts); the shell just coordinates selection and attaching.
/// The detection inbox (slice 12) and menu-bar companion (slice 13) build on this. (PLAN slice 11)
@MainActor
@Observable
final class MainWindowModel {
    private(set) var streams: [VitalsModel]
    private(set) var selectedIndex: Int

    /// The stream the center timeline shows, or `nil` when nothing is attached (empty state).
    var selected: VitalsModel? {
        streams.indices.contains(selectedIndex) ? streams[selectedIndex] : nil
    }

    init(streams: [VitalsModel] = [], selectedIndex: Int = 0) {
        self.streams = streams
        self.selectedIndex = selectedIndex
    }

    /// Show a different attached target's stream. Out-of-range indices are ignored.
    func select(_ index: Int) {
        guard streams.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Attach a newly-picked process: add its stream and make it the selected one.
    func attach(_ stream: VitalsModel) {
        streams.append(stream)
        selectedIndex = streams.count - 1
    }
}

// MARK: - Menu-bar companion (fleet-wide glance)

/// The menu-bar dropdown (SPEC §8; PLAN slice 13) reads the whole fleet at once: a header count,
/// the recent detections across every attached target, and `Pause all` / `Resume all`. These are
/// pure folds over `streams`, so the companion binds to them without any `NSStatusItem` in tests.
extension MainWindowModel {
    /// Header line, e.g. `Monitoring 2 targets`.
    var monitoringSummary: String {
        "Monitoring \(streams.count) target\(streams.count == 1 ? "" : "s")"
    }

    /// Whether every attached stream is frozen — drives the `Pause all` / `Resume all` emphasis.
    /// An empty fleet is not "all paused": there is nothing to pause.
    var allPaused: Bool { !streams.isEmpty && streams.allSatisfy(\.isPaused) }

    /// The recent detections across all targets, newest-first within each and capped at three —
    /// a glance, not the full inbox. Cross-target ordering falls back to attach order (the Domain
    /// has no wall clock to interleave feeds by; documented in PROGRESS). (SPEC §8)
    var recentDetections: [Detection] { Array(streams.flatMap(\.detections).prefix(3)) }

    /// Freeze every attached stream's poller.
    func pauseAll() { streams.forEach { $0.setPaused(true) } }

    /// Resume every attached stream's poller.
    func resumeAll() { streams.forEach { $0.setPaused(false) } }
}
