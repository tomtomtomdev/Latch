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

    private func device(_ name: String, paired: Bool = true, devMode: Bool = true) -> Device {
        Device(udid: "udid-\(name)", name: name, platform: "iOS",
               isPaired: paired, developerModeEnabled: devMode, isConnected: true)
    }

    // load() also pulls connected iOS devices, so the attach sheet can surface them. (PLAN slice 9)
    @Test func load_populatesDevicesFromDiscovery() async {
        let model = TargetPickerModel(discovery: FakeTargetDiscovery(
            targets: [], devicesToReturn: [device("iPhone")]
        ))

        await model.load()

        #expect(model.devices.map(\.name) == ["iPhone"])
    }

    // Device discovery is best-effort: a `devicectl` failure (e.g. not installed) leaves the
    // process list intact and does not surface as the picker's error. (SPEC §1; PLAN slice 9)
    @Test func load_deviceFailureLeavesProcessesIntact() async {
        let model = TargetPickerModel(discovery: FakeTargetDiscovery(
            targets: [target(1, "Safari")], deviceError: FakeTargetDiscovery.Failure.scripted
        ))

        await model.load()

        #expect(model.targets.map(\.displayName) == ["Safari"])
        #expect(model.devices.isEmpty)
        #expect(model.errorMessage == nil)
    }
}
