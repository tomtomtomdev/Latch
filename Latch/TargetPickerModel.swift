import Foundation
import LatchDomain

/// Presentation state for the local-process picker: loads attachable targets, filters
/// them by the search field, and records the one the user latches onto. Depends only on
/// the Domain `TargetDiscovery` abstraction, so it is driven by a fake in tests.
/// (SPEC §3; PLAN slice 1)
@MainActor
@Observable
final class TargetPickerModel {
    private(set) var targets: [Target] = []
    /// Connected iOS devices surfaced alongside local processes. Informational for now: on-device
    /// app enumeration is deferred, so an eligible device is shown but not yet attachable. (SPEC §1)
    private(set) var devices: [Device] = []
    private(set) var selected: Target?
    private(set) var errorMessage: String?
    var searchText: String = ""

    private let discovery: TargetDiscovery

    init(discovery: TargetDiscovery) {
        self.discovery = discovery
    }

    var filteredTargets: [Target] {
        guard !searchText.isEmpty else { return targets }
        return targets.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    func load() async {
        do {
            targets = try await discovery.localProcesses()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await loadDevices()
    }

    /// Load connected iOS devices best-effort: `devicectl` may be absent or fail, and that must
    /// not blank the process list or masquerade as a process-discovery error. (SPEC §1; PLAN slice 9)
    private func loadDevices() async {
        devices = (try? await discovery.devices()) ?? []
    }

    func select(_ target: Target) {
        selected = target
    }
}
