import Foundation
import Testing
import LatchDomain
@testable import LatchData

/// Slice 10: the JSON serializer is the Data-layer boundary that turns a Domain `SessionReport`
/// into the shareable bundle and back. The Domain stays Foundation-free; `JSONEncoder`/`Decoder`
/// live here. (SPEC §3, §4; PLAN slice 10)
struct JSONReportSerializerTests {
    private func fullReport() -> SessionReport {
        let target = Target(
            id: "p-501", kind: .localMac, pid: 501,
            executablePath: "/Apps/Demo", bundleID: "com.example.Demo", displayName: "Demo"
        )
        let samples = [
            MetricSample(
                cpuPercent: 12.5, physFootprintBytes: 10_485_760, residentBytes: 9_000_000,
                threadCount: 4, netInBytesPerSec: 1_000, netOutBytesPerSec: 2_000, energyWatts: 1.5
            ),
        ]
        let alerts = [Alert(signal: .cpuSpike, severity: .warning, sample: samples[0])]
        let diagnostics = [
            DiagnosticResult(
                kind: .leaks, summary: "1 leak",
                findings: [Finding(
                    title: "ROOT LEAK", byteCount: 32, instanceCount: 1,
                    backtrace: ["frame0", "frame1"]
                )],
                tracePath: "/tmp/x.trace"
            ),
        ]
        return ExportReport()(
            target: target, metrics: samples, alerts: alerts, diagnostics: diagnostics,
            liveProvenance: [MetricProvenance(signal: .cpuSpike, source: "proc_pid_rusage", mode: .livePoll)]
        )
    }

    // The whole report survives encode → decode unchanged: timeline, alerts, diagnostics,
    // trace paths, and provenance all round-trip.
    @Test func encodeThenDecode_roundTripsTheReport() throws {
        let report = fullReport()
        let serializer = JSONReportSerializer()

        let decoded = try serializer.decode(serializer.encode(report))

        #expect(decoded == report)
    }

    // Provenance per metric is actually written into the bundle (human-inspectable), not just
    // reconstructed from defaults on decode.
    @Test func encodedJSON_containsProvenancePerMetric() throws {
        let data = try JSONReportSerializer().encode(fullReport())

        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("provenance"))
        #expect(json.contains("proc_pid_rusage"))
        #expect(json.contains("livePoll"))
    }
}
