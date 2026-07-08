import LatchDomain

/// Test double for `TargetDiscovery`: returns canned local processes and iOS devices so
/// view-model tests run without touching libproc or `devicectl`. `deviceError`, when set, makes
/// `devices()` throw — exercising the picker's best-effort device discovery (a device-enumeration
/// failure must not blank the process list). (SPEC §6)
struct FakeTargetDiscovery: TargetDiscovery {
    enum Failure: Error { case scripted }

    let targets: [Target]
    var devicesToReturn: [Device] = []
    var deviceError: Error?

    func localProcesses() async throws -> [Target] {
        targets
    }

    func devices() async throws -> [Device] {
        if let deviceError { throw deviceError }
        return devicesToReturn
    }
}
