import Foundation
import LatchDomain

/// Serializes a Domain `SessionReport` to and from the shareable JSON bundle. The Domain stays
/// Foundation-free (it only declares `Codable` conformance); this adapter owns the `JSONEncoder`/
/// `JSONDecoder` I/O. Output is pretty-printed with sorted keys so the bundle is human-readable
/// and stable (diffable across exports). (SPEC §3, §4; PLAN slice 10)
public struct JSONReportSerializer: Sendable {
    public init() {}

    public func encode(_ report: SessionReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    public func decode(_ data: Data) throws -> SessionReport {
        try JSONDecoder().decode(SessionReport.self, from: data)
    }
}
