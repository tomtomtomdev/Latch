import Foundation
import LatchDomain
import LatchData

extension VitalsModel {
    /// A `VitalsModel` wired to the real Data-layer adapters for a latched target: libproc
    /// vitals, `nettop` network, `powermetrics` energy, and the on-demand diagnostic runners
    /// (leaks / trace / zombies / hitches). Centralized here so the shell and the attach flow
    /// build streams identically. (SPEC §3.2; PLAN slice 11)
    static func live(for target: Target) -> VitalsModel {
        let runner = ProcessCommandRunner()
        let tempDirectory = FileManager.default.temporaryDirectory.path
        return VitalsModel(
            source: LibprocMetricsSource(),
            networkSource: NettopMetricsSource(commandRunner: runner),
            energySource: PowermetricsSource(commandRunner: runner),
            leakChecker: LeaksCLIRunner(commandRunner: runner),
            traceRecorder: XctraceDiagnosticRunner(
                commandRunner: runner,
                outputDirectory: tempDirectory
            ),
            zombieRunner: ZombieDiagnosticRunner(commandRunner: runner),
            hitchRunner: SampleDiagnosticRunner(commandRunner: runner),
            hitchTraceRecorder: XctraceDiagnosticRunner(
                commandRunner: runner,
                outputDirectory: tempDirectory,
                kind: .hitches
            ),
            target: target,
            pid: target.pid ?? -1
        )
    }
}
