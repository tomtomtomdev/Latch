import Darwin
import LatchDomain

/// Real `NetworkSource` backed by `nettop`. Runs the logging-mode command through the
/// `CommandRunner` seam and maps its CSV to a cumulative `NetworkReading`; the caller
/// derives a per-second rate from successive readings. The `nettop`/CSV types stay inside
/// this adapter. (SPEC §3.2; PLAN slice 4)
///
/// Command and format verified on macOS 15.6 (`man nettop`, live output): `-P` collapses
/// to a per-process summary, `-L 1` emits one CSV sample then exits, `-J` selects only the
/// requested columns, `-p <pid>` filters to the target. CSV mode always prints raw integer
/// byte counts. Output is a header row `,bytes_in,bytes_out,` followed by one
/// `<name>.<pid>,<bytes_in>,<bytes_out>,` row per matched process. (SPEC §7)
public struct NettopMetricsSource: NetworkSource {
    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner) {
        self.commandRunner = commandRunner
    }

    public func sample(pid: Int32) async throws -> NetworkReading {
        let result = try await commandRunner.run(
            "/usr/bin/nettop",
            arguments: ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-p", "\(pid)"]
        )
        return Self.parse(result.stdout, wallClockNanos: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW))
    }

    /// Sum the `bytes_in`/`bytes_out` columns across every data row. The header row and any
    /// blank lines are skipped naturally because their second/third fields are not numbers.
    static func parse(_ stdout: String, wallClockNanos: UInt64) -> NetworkReading {
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        for line in stdout.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let rowIn = UInt64(fields[1]),
                  let rowOut = UInt64(fields[2]) else { continue }
            bytesIn += rowIn
            bytesOut += rowOut
        }
        return NetworkReading(bytesIn: bytesIn, bytesOut: bytesOut, wallClockNanos: wallClockNanos)
    }
}
