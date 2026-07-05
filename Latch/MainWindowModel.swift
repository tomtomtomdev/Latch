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
