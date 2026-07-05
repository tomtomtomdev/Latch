import Testing
import LatchDomain
@testable import Latch

/// The main window shell coordinates the attached targets: which one's stream the center
/// timeline shows, and attaching a newly-picked process. Each attached target owns its own
/// `VitalsModel` stream. (Design handoff sidebar; PLAN slice 11)
@MainActor
struct MainWindowModelTests {
    private func stream(id: String) -> VitalsModel {
        VitalsModel(
            source: FakeMetricsSource(readings: []),
            target: Target(id: id, kind: .localMac, pid: 1, displayName: id),
            pid: 1
        )
    }

    // Selecting a sidebar row swaps which target's stream is the selected (streamed) one.
    @Test func select_swapsStreamedTarget() {
        let model = MainWindowModel(streams: [stream(id: "A"), stream(id: "B")])
        #expect(model.selected?.target?.id == "A")

        model.select(1)

        #expect(model.selected?.target?.id == "B")
    }

    // With nothing attached there is no selected stream — the window shows its empty state.
    @Test func selected_isNilWhenNothingAttached() {
        let model = MainWindowModel()
        #expect(model.selected == nil)
    }

    // An out-of-range selection is ignored rather than crashing.
    @Test func select_ignoresOutOfRangeIndex() {
        let model = MainWindowModel(streams: [stream(id: "A")])
        model.select(9)
        #expect(model.selected?.target?.id == "A")
    }

    // Attaching a picked process adds its stream and makes it the selected one.
    @Test func attach_addsStreamAndSelectsIt() {
        let model = MainWindowModel(streams: [stream(id: "A")])

        model.attach(stream(id: "B"))

        #expect(model.streams.count == 2)
        #expect(model.selected?.target?.id == "B")
    }
}
