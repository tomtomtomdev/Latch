import Testing
import LatchDomain
@testable import Latch

/// The sidebar health dot summarizes a target's live alert state into one of three levels.
/// It is a pure fold over the active alerts, so it is testable independent of the poll
/// pipeline. (Design handoff sidebar; PLAN slice 11)
struct TargetHealthTests {
    private let sample = MetricSample(
        cpuPercent: 0, physFootprintBytes: 0, residentBytes: 0, threadCount: 0
    )

    private func alert(_ signal: SignalKind, _ severity: AlertSeverity) -> Alert {
        Alert(signal: signal, severity: severity, sample: sample)
    }

    // No active alerts → the target is healthy.
    @Test func health_isHealthy_withNoAlerts() {
        #expect(TargetHealth.from(alerts: []) == .healthy)
    }

    // A warning-level alert → warning.
    @Test func health_isWarning_withAWarningAlert() {
        #expect(TargetHealth.from(alerts: [alert(.cpuSpike, .warning)]) == .warning)
    }

    // Any critical alert dominates, even amid warnings.
    @Test func health_isCritical_whenAnyAlertIsCritical() {
        let alerts = [alert(.cpuSpike, .warning), alert(.battery, .critical)]
        #expect(TargetHealth.from(alerts: alerts) == .critical)
    }
}
