import Testing
import Foundation
import LatchDomain
@testable import LatchData

struct NettopMetricsSourceTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Fixtures")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func source(returning stdout: String) -> (NettopMetricsSource, RecordingCommandRunner) {
        let runner = RecordingCommandRunner(result: CommandResult(stdout: stdout, stderr: "", exitCode: 0))
        return (NettopMetricsSource(commandRunner: runner), runner)
    }

    // The CSV data row's bytes_in/bytes_out columns become the cumulative reading. (PLAN slice 4)
    @Test func sample_parsesCumulativeBytesFromTrafficRow() async throws {
        let (nettop, _) = source(returning: try fixture("nettop-traffic"))

        let reading = try await nettop.sample(pid: 148)

        #expect(reading.bytesIn == 162_295)
        #expect(reading.bytesOut == 754_678)
        #expect(reading.wallClockNanos > 0)
    }

    // Header-only output (no open sockets, or pid not found) reads as zero bytes, not an
    // error — a process with no network is a valid zero rate. (SPEC §6)
    @Test func sample_returnsZeroWhenNoSockets() async throws {
        let (nettop, _) = source(returning: try fixture("nettop-no-sockets"))

        let reading = try await nettop.sample(pid: 999_999)

        #expect(reading.bytesIn == 0)
        #expect(reading.bytesOut == 0)
    }

    // Multiple matched rows are summed so a name that matches several pids totals correctly.
    @Test func sample_sumsBytesAcrossRows() async throws {
        let (nettop, _) = source(returning: try fixture("nettop-multi-row"))

        let reading = try await nettop.sample(pid: 219)

        #expect(reading.bytesIn == 5_084_325_804 + 77_873)
        #expect(reading.bytesOut == 565_458_614 + 106_698)
    }

    // The adapter runs exactly the PLAN command — the flags are pinned so a regression in
    // them is caught here rather than at runtime. (PLAN slice 4; SPEC §3.2)
    @Test func sample_invokesNettopWithLoggingFlagsForThePid() async throws {
        let (nettop, runner) = source(returning: try fixture("nettop-no-sockets"))

        _ = try await nettop.sample(pid: 4242)

        #expect(runner.executablePath == "/usr/bin/nettop")
        #expect(runner.arguments == ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-p", "4242"])
    }
}
