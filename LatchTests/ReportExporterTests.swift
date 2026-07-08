import Testing
import Foundation
import LatchDomain
import LatchData
@testable import Latch

/// Writing a `SessionReport` to disk: the JSON bundle plus a Markdown summary sidecar. The
/// `NSSavePanel` that picks the destination is the only untestable part; this seam writes the
/// bytes and is exercised against a temp directory. (SPEC §4, §8; PLAN slice 10)
struct ReportExporterTests {
    private func report() -> SessionReport {
        SessionReport(
            target: Target(id: "42", kind: .localMac, pid: 42, displayName: "Leaky"),
            metrics: [], alerts: [], diagnostics: [],
            provenance: [MetricProvenance(signal: .cpuSpike, source: "proc_pid_rusage", mode: .livePoll)]
        )
    }

    private func tempBaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("latch-export-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    // Writing emits a JSON bundle that round-trips back to the same report.
    @Test func write_emitsRoundTrippableJSON() throws {
        let base = tempBaseURL()
        defer { try? FileManager.default.removeItem(at: base.deletingPathExtension().appendingPathExtension("json")) }

        let jsonURL = try ReportExporter().write(report(), to: base)

        let decoded = try JSONReportSerializer().decode(Data(contentsOf: jsonURL))
        #expect(decoded.target.displayName == "Leaky")
    }

    // A Markdown summary sidecar is written beside the JSON, regardless of the chosen extension.
    @Test func write_emitsMarkdownSidecar() throws {
        let base = tempBaseURL()
        let markdownURL = base.deletingPathExtension().appendingPathExtension("md")
        defer {
            try? FileManager.default.removeItem(at: markdownURL)
            try? FileManager.default.removeItem(at: base.deletingPathExtension().appendingPathExtension("json"))
        }

        try ReportExporter().write(report(), to: base)

        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        #expect(markdown.contains("# Latch Session Report — Leaky"))
    }
}
