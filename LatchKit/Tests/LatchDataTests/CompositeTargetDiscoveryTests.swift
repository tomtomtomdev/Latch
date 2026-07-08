import Testing
import LatchDomain
@testable import LatchData

/// `CompositeTargetDiscovery` fuses several single-purpose `TargetDiscovery` adapters into one:
/// the libproc adapter serves local processes, the devicectl adapter serves iOS devices, and the
/// picker depends on the single fused protocol. (SPEC §3.1, §3.2; PLAN slices 1, 9)
struct CompositeTargetDiscoveryTests {
    /// Serves only the target kind it is handed; the rest fall through to the protocol's empty
    /// defaults — mirroring how the real libproc / devicectl adapters each serve one kind.
    private struct StubDiscovery: TargetDiscovery {
        var processes: [Target] = []
        var deviceList: [Device] = []
        func localProcesses() async throws -> [Target] { processes }
        func devices() async throws -> [Device] { deviceList }
    }

    private func target(_ name: String) -> Target {
        Target(id: name, kind: .localMac, pid: 1, displayName: name)
    }

    private func device(_ name: String) -> Device {
        Device(udid: name, name: name, platform: "iOS",
               isPaired: true, developerModeEnabled: true, isConnected: true)
    }

    // Local processes are merged across every source in order.
    @Test func localProcesses_mergesAcrossSources() async throws {
        let composite = CompositeTargetDiscovery([
            StubDiscovery(processes: [target("Safari")]),
            StubDiscovery(deviceList: [device("iPhone")]),
        ])

        let processes = try await composite.localProcesses()

        #expect(processes.map(\.displayName) == ["Safari"])
    }

    // Devices are merged across every source, so the device-serving adapter surfaces through.
    @Test func devices_mergesAcrossSources() async throws {
        let composite = CompositeTargetDiscovery([
            StubDiscovery(processes: [target("Safari")]),
            StubDiscovery(deviceList: [device("iPhone")]),
        ])

        let devices = try await composite.devices()

        #expect(devices.map(\.name) == ["iPhone"])
    }
}
