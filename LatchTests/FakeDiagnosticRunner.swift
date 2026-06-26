import LatchDomain

/// Test double for the deep-diagnostic port: returns a scripted `DiagnosticResult`, or throws
/// a scripted error to exercise `VitalsModel`'s failure-message path — without shelling out to
/// `leaks`/`xctrace`. Main-actor confined in tests, hence `@unchecked Sendable`. (SPEC §6)
final class FakeDiagnosticRunner: DiagnosticRunner, @unchecked Sendable {
    let kind: DiagnosticKind = .leaks
    let requiresRelaunch = false

    private let result: DiagnosticResult?
    private let error: Error?
    private(set) var ranTargets: [Target] = []

    init(result: DiagnosticResult) {
        self.result = result
        self.error = nil
    }

    init(failsWith error: Error) {
        self.result = nil
        self.error = error
    }

    func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult {
        ranTargets.append(target)
        if let error { throw error }
        return result ?? DiagnosticResult(kind: .leaks, summary: "", findings: [])
    }
}
