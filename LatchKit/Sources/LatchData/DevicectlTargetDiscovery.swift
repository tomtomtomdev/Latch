import Foundation
import LatchDomain

/// Discovers connected iOS devices via Apple's Core Device CLI (`xcrun devicectl`), behind the
/// `CommandRunner` seam. `devicectl` writes its results only to a JSON file given via
/// `--json-output` (its documented, version-stable interface — stdout is explicitly *not*
/// guaranteed stable), so the adapter points it at a file under `workingDirectory`, reads that
/// file, and decodes it into Domain `Device`s. The hardware `udid` it surfaces is the
/// identifier `xctrace --device <udid>` keys on (verified against `xctrace list devices`).
/// (SPEC §1, §3.2; PLAN slice 9)
///
/// On-device **app/process enumeration** (`devicectl device info apps`/`processes`) is
/// **deferred**: it requires an actively-connected device, which can't be exercised in the
/// automated flow (paired devices here are tunnel-disconnected — `xctrace` lists them
/// "Offline"), so a real populated fixture can't be captured to verify the entry schema. Per
/// SPEC §7 (verify-then-use) and §1 (no fake capabilities) that parser is built and validated
/// in the manual integration smoke; this adapter ships the verified `list devices` path plus
/// the verified `device info apps` command. The Domain dev-signed eligibility gate
/// (`Device.eligibility(forApp:)`) is built and tested, ready for that enumeration. (SPEC §6)
public struct DevicectlTargetDiscovery: TargetDiscovery {
    private let commandRunner: CommandRunner
    private let workingDirectory: String

    public init(commandRunner: CommandRunner, workingDirectory: String = NSTemporaryDirectory()) {
        self.commandRunner = commandRunner
        self.workingDirectory = workingDirectory
    }

    public func devices() async throws -> [Device] {
        let json = try await runJSON(
            arguments: ["devicectl", "list", "devices", "--quiet"],
            outputFilename: "latch-devicectl-devices.json"
        )
        return try JSONDecoder()
            .decode(DevicectlDeviceList.self, from: json)
            .result.devices
            .compactMap(Self.device(from:))
    }

    /// Runs an `xcrun devicectl` command that writes its JSON to a file under `workingDirectory`,
    /// then reads the file back. Throws `TargetDiscoveryError.toolFailed` on a non-zero exit.
    private func runJSON(arguments: [String], outputFilename: String) async throws -> Data {
        let outputPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent(outputFilename).path
        let result = try await commandRunner.run(
            "/usr/bin/xcrun", arguments: arguments + ["--json-output", outputPath]
        )
        guard result.exitCode == 0 else {
            throw TargetDiscoveryError.toolFailed(exitCode: result.exitCode, message: result.stderr)
        }
        return try Data(contentsOf: URL(fileURLWithPath: outputPath))
    }

    /// Maps one decoded device entry to a Domain `Device`, deriving the boolean eligibility
    /// facts from devicectl's string states. A device with no hardware UDID can't be routed to,
    /// so it is dropped.
    private static func device(from entry: DevicectlDeviceList.DeviceEntry) -> Device? {
        guard let udid = entry.hardwareProperties.udid else { return nil }
        return Device(
            udid: udid,
            name: entry.deviceProperties.name ?? udid,
            platform: entry.hardwareProperties.platform ?? "",
            osVersion: entry.deviceProperties.osVersionNumber,
            isPaired: entry.connectionProperties.pairingState == "paired",
            developerModeEnabled: entry.deviceProperties.developerModeStatus == "enabled",
            isConnected: entry.connectionProperties.tunnelState == "connected"
        )
    }
}

/// Decodes the subset of `devicectl list devices` JSON Latch needs. Only the fields that drive a
/// Domain `Device` are modelled; the rest of the (large) schema is ignored. Captured + verified
/// against real output on Xcode 26.5 / devicectl 518.31 (jsonVersion 3). (SPEC §6, §7)
private struct DevicectlDeviceList: Decodable {
    let result: Result

    struct Result: Decodable {
        let devices: [DeviceEntry]
    }

    struct DeviceEntry: Decodable {
        let connectionProperties: ConnectionProperties
        let deviceProperties: DeviceProperties
        let hardwareProperties: HardwareProperties
    }

    struct ConnectionProperties: Decodable {
        let pairingState: String?
        let tunnelState: String?
    }

    struct DeviceProperties: Decodable {
        let name: String?
        let developerModeStatus: String?
        let osVersionNumber: String?
    }

    struct HardwareProperties: Decodable {
        let udid: String?
        let platform: String?
    }
}
