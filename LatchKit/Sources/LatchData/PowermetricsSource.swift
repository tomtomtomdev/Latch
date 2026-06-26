import Foundation
import LatchDomain

/// Real `EnergySource` backed by `powermetrics`. Runs the privileged tasks sampler through
/// the `CommandRunner` seam and maps its property-list output to a per-process energy
/// impact. The `powermetrics`/plist types stay inside this adapter. (SPEC §3.2; PLAN slice 5)
///
/// `powermetrics` requires **root**. This adapter does not escalate privilege itself — it
/// runs the command through whatever `CommandRunner` it is given; an unprivileged run exits
/// non-zero and surfaces as `EnergyMeasurementError.unavailable`, which the caller treats as
/// the signal to degrade to the `ri_energy_nj` estimate. A real escalation path
/// (`SMAppService`/authorization helper) is a later slice. (SPEC §1, §5)
///
/// Command per `man powermetrics` (macOS 15.6): `--samplers tasks` reads per-process
/// activity, `--show-process-energy` adds the per-process energy impact number, `-f plist`
/// emits a machine-readable property list, `-n 1` takes a single sample over `-i 1000` ms.
///
/// ⚠️ The plist's `energy_impact` key name is assumed from the documented format and has
/// NOT been validated against a real root run — see the slice-5 decision log and the
/// fixtures README. (SPEC §6, §7)
public struct PowermetricsSource: EnergySource {
    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }

    private static let arguments = [
        "--samplers", "tasks", "--show-process-energy", "-f", "plist", "-n", "1", "-i", "1000",
    ]

    public func measuredEnergyImpact(pid: Int32) async throws -> Double {
        let result = try await commandRunner.run("/usr/bin/powermetrics", arguments: Self.arguments)
        guard result.exitCode == 0 else { throw EnergyMeasurementError.unavailable }
        return try Self.parse(result.stdout, pid: pid)
    }

    /// Pull the `energy_impact` for `pid` from the tasks plist. `powermetrics` emits plists
    /// NUL-separated, so a trailing NUL (and surrounding whitespace) is stripped before
    /// parsing the single `-n 1` sample.
    static func parse(_ stdout: String, pid: Int32) throws -> Double {
        let trailing = CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines)
        let cleaned = stdout.trimmingCharacters(in: trailing)
        guard let data = cleaned.data(using: .utf8),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let tasks = (root as? [String: Any])?["tasks"] as? [[String: Any]] else {
            throw EnergyMeasurementError.unavailable
        }
        for task in tasks where (task["pid"] as? Int).map({ Int32($0) }) == pid {
            guard let impact = task["energy_impact"] as? Double else { break }
            return impact
        }
        throw EnergyMeasurementError.processNotFound(pid: pid)
    }
}
