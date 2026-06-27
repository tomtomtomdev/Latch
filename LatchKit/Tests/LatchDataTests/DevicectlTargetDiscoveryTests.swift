import Testing
import Foundation
import LatchDomain
@testable import LatchData

/// Slice 9: `DevicectlTargetDiscovery` enumerates connected iOS devices by parsing the JSON
/// `xcrun devicectl list devices` writes to a file. Fixtures are **real captured** output
/// (sanitized) from two paired iPhones — one with Developer Mode off (ineligible), one with
/// it on (eligible) — so the parse and the eligibility tagging are pinned against genuine
/// devicectl shape, not a guess. (SPEC §1, §3.2, §6; PLAN slice 9)
struct DevicectlTargetDiscoveryTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func tempDirectory() throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("latch-devicectl-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    // The real `list devices` JSON for two paired iPhones maps to two Devices carrying the
    // hardware UDID (the `xctrace --device` key), name, platform, OS version, pairing, and
    // Developer-Mode state — and neither shows as connected (both tunnels are down). (PLAN slice 9)
    @Test func devices_parsesListDevicesFixtureIntoDevices() async throws {
        let runner = DevicectlStubRunner(json: try fixture("devicectl-devices"))
        let discovery = DevicectlTargetDiscovery(commandRunner: runner, workingDirectory: try tempDirectory())

        let devices = try await discovery.devices()

        #expect(devices.map(\.udid) == ["00008110-000000000000001A", "00008030-000000000000002E"])
        #expect(devices.map(\.name) == ["Latch Test iPhone (dev mode off)", "Latch Test iPhone"])
        #expect(devices.allSatisfy { $0.platform == "iOS" })
        #expect(devices.map(\.osVersion) == ["18.5", "18.1.1"])
        #expect(devices.allSatisfy { $0.isPaired })
        #expect(devices.map(\.developerModeEnabled) == [false, true])
        #expect(devices.allSatisfy { !$0.isConnected })
    }

    // The parsed devices feed straight into the Domain eligibility verdict: the Developer-Mode-off
    // device is ineligible (with the honest reason), the other is eligible. (SPEC §1; PLAN slice 9)
    @Test func devices_carryTheirEligibilityVerdict() async throws {
        let runner = DevicectlStubRunner(json: try fixture("devicectl-devices"))
        let discovery = DevicectlTargetDiscovery(commandRunner: runner, workingDirectory: try tempDirectory())

        let devices = try await discovery.devices()

        #expect(devices[0].profilingEligibility == .ineligible(.developerModeDisabled))
        #expect(devices[1].profilingEligibility == .eligible)
    }

    // The adapter runs exactly the verified command, writing JSON to a file under its working
    // directory (devicectl's only stable output channel). The flags are pinned so a regression
    // is caught here. (PLAN slice 9; SPEC §3.2)
    @Test func devices_invokesVerifiedListDevicesCommand() async throws {
        let dir = try tempDirectory()
        let runner = DevicectlStubRunner(json: try fixture("devicectl-devices"))
        let discovery = DevicectlTargetDiscovery(commandRunner: runner, workingDirectory: dir)

        _ = try await discovery.devices()

        let expectedPath = URL(fileURLWithPath: dir)
            .appendingPathComponent("latch-devicectl-devices.json").path
        #expect(runner.executablePath == "/usr/bin/xcrun")
        #expect(runner.arguments == [
            "devicectl", "list", "devices", "--quiet", "--json-output", expectedPath,
        ])
    }

    // When devicectl exits non-zero (no Core Device daemon, etc.) the adapter surfaces the
    // failure honestly rather than returning a hollow empty list. (SPEC §1)
    @Test func devices_throwsToolFailed_whenDevicectlExitsNonZero() async throws {
        let runner = DevicectlStubRunner(json: "", exitCode: 1)
        let discovery = DevicectlTargetDiscovery(commandRunner: runner, workingDirectory: try tempDirectory())

        await #expect(throws: TargetDiscoveryError.self) {
            _ = try await discovery.devices()
        }
    }
}
