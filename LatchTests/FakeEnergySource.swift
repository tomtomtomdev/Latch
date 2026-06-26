import LatchDomain

/// Test double for the measured-energy port: returns a scripted impact, or throws a
/// scripted `EnergyMeasurementError` to exercise `VitalsModel`'s degrade-to-estimate path
/// without shelling out to `powermetrics`. Main-actor confined in tests, hence
/// `@unchecked Sendable`. (SPEC §6)
final class FakeEnergySource: EnergySource, @unchecked Sendable {
    private let impact: Double?
    private let error: EnergyMeasurementError?
    private(set) var callCount = 0

    init(impact: Double) {
        self.impact = impact
        self.error = nil
    }

    init(failsWith error: EnergyMeasurementError) {
        self.impact = nil
        self.error = error
    }

    func measuredEnergyImpact(pid: Int32) async throws -> Double {
        callCount += 1
        if let error { throw error }
        return impact ?? 0
    }
}
