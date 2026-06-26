import Testing
import LatchDomain
@testable import Latch

@MainActor
struct TargetPickerModelTests {
    private func target(_ pid: Int32, _ name: String) -> Target {
        Target(id: String(pid), kind: .localMac, pid: pid, displayName: name)
    }

    // load() pulls targets from discovery into the model. (PLAN slice 1)
    @Test func load_populatesTargetsFromDiscovery() async {
        let model = TargetPickerModel(discovery: FakeTargetDiscovery(
            targets: [target(1, "Safari"), target(2, "Xcode")]
        ))

        await model.load()

        #expect(model.targets.map(\.displayName) == ["Safari", "Xcode"])
    }

    // The search field narrows the list case-insensitively by display name. (PLAN slice 1)
    @Test func filteredTargets_matchesSearchTextCaseInsensitively() async {
        let model = TargetPickerModel(discovery: FakeTargetDiscovery(
            targets: [target(1, "Safari"), target(2, "Xcode"), target(3, "SafariBeta")]
        ))
        await model.load()

        model.searchText = "safari"

        #expect(model.filteredTargets.map(\.displayName) == ["Safari", "SafariBeta"])
    }

    // Selecting a target records it as the latched target. (PLAN slice 1)
    @Test func select_setsTheLatchedTarget() async {
        let model = TargetPickerModel(discovery: FakeTargetDiscovery(targets: []))
        let picked = target(7, "Mail")

        model.select(picked)

        #expect(model.selected == picked)
    }
}
