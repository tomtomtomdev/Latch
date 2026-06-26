import LatchDomain

/// Test double for `TargetDiscovery`: returns canned targets so view-model tests run
/// without touching libproc. (SPEC §6)
struct FakeTargetDiscovery: TargetDiscovery {
    let targets: [Target]

    func localProcesses() async throws -> [Target] {
        targets
    }
}
