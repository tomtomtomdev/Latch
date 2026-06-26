import LatchDomain

/// Test double for the deep-diagnostic port: returns a scripted `DiagnosticResult`, or throws
/// a scripted error to exercise `VitalsModel`'s failure-message path — without shelling out to
/// `leaks`/`xctrace`. Main-actor confined in tests, hence `@unchecked Sendable`. (SPEC §6)
final class FakeDiagnosticRunner: DiagnosticRunner, @unchecked Sendable {
    let kind: DiagnosticKind
    let requiresRelaunch: Bool

    private let result: DiagnosticResult?
    private let error: Error?
    private(set) var ranTargets: [Target] = []

    init(kind: DiagnosticKind = .leaks, requiresRelaunch: Bool = false, result: DiagnosticResult) {
        self.kind = kind
        self.requiresRelaunch = requiresRelaunch
        self.result = result
        self.error = nil
    }

    init(kind: DiagnosticKind = .leaks, requiresRelaunch: Bool = false, failsWith error: Error) {
        self.kind = kind
        self.requiresRelaunch = requiresRelaunch
        self.result = nil
        self.error = error
    }

    func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult {
        ranTargets.append(target)
        if let error { throw error }
        return result ?? DiagnosticResult(kind: kind, summary: "", findings: [])
    }
}
