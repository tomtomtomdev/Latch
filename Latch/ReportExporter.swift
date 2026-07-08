import Foundation
import LatchDomain
import LatchData

/// Writes a `SessionReport` to disk as a JSON bundle plus a human-readable Markdown summary
/// sidecar. The Data-layer `JSONReportSerializer` owns the encoding; this just derives the two
/// file URLs from the chosen base and writes the bytes. The `NSSavePanel` that supplies the base
/// URL stays in the view — this seam is pure I/O so it is testable. (SPEC §4, §8; PLAN slice 10)
nonisolated struct ReportExporter {
    private let serializer = JSONReportSerializer()

    /// Writes `<base>.json` (the bundle) and `<base>.md` (the summary), replacing whatever
    /// extension `baseURL` carries. Returns the JSON bundle's URL.
    @discardableResult
    func write(_ report: SessionReport, to baseURL: URL) throws -> URL {
        let jsonURL = baseURL.deletingPathExtension().appendingPathExtension("json")
        let markdownURL = baseURL.deletingPathExtension().appendingPathExtension("md")
        try serializer.encode(report).write(to: jsonURL)
        try Data(report.markdownSummary.utf8).write(to: markdownURL)
        return jsonURL
    }
}
