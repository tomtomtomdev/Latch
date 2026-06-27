// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Enumerates targets the user may latch onto. Domain owns the abstraction; the Data layer
/// supplies a libproc-backed local implementation (`LibprocTargetDiscovery`) and a
/// devicectl-backed iOS implementation (`DevicectlTargetDiscovery`). (SPEC §3.1, §3.2;
/// PLAN slices 1, 9)
public protocol TargetDiscovery: Sendable {
    /// Same-UID local macOS processes — the only ones a debugger-entitled tool can
    /// attach to. (SPEC §1)
    func localProcesses() async throws -> [Target]

    /// Connected iOS devices the user might profile apps on. (SPEC §1, §3.1; PLAN slice 9)
    func devices() async throws -> [Device]

    /// Apps installed on a given device, as attachable targets. (SPEC §3.1; PLAN slice 9)
    func apps(on device: Device) async throws -> [Target]
}

/// Default "this source offers none of that kind" implementations, so each adapter overrides
/// only the target sources it actually serves: the libproc discovery surfaces local processes
/// (and no devices/apps), the devicectl discovery surfaces devices (and no local processes).
/// (SPEC §3.1)
extension TargetDiscovery {
    public func localProcesses() async throws -> [Target] { [] }
    public func devices() async throws -> [Device] { [] }
    public func apps(on device: Device) async throws -> [Target] { [] }
}
