import Foundation
import LatchDomain

/// Presentation state for the live vitals dashboard of one latched target. Polls a
/// `MetricsSource` on a fixed cadence, derives a `MetricSample` from each consecutive
/// pair of readings, and keeps a bounded ring buffer of history for the charts. Depends
/// only on the Domain `MetricsSource` abstraction, so it is driven by a fake in tests.
/// (SPEC §3, §4; PLAN slice 2)
@MainActor
@Observable
final class VitalsModel {
    private(set) var samples: [MetricSample] = []
    private(set) var alerts: [Alert] = []
    private(set) var thresholds: [Threshold]
    private(set) var errorMessage: String?
    /// The last on-demand `powermetrics` measurement (energy impact), or `nil` when none has
    /// been taken or the privileged read degraded to the estimate. (SPEC §3.3, §5)
    private(set) var measuredEnergy: Double?
    /// Why the measured-energy read is unavailable (e.g. needs root), shown beside the
    /// estimate so the degrade is honest rather than silent. (SPEC §1, §5)
    private(set) var energyMessage: String?
    /// The most recent leak-check result (`leaks` CLI findings + summary), or `nil` until a
    /// check is run. (SPEC §1; PLAN slice 6)
    private(set) var leakReport: DiagnosticResult?
    /// Why the last leak check could not complete (target exited, etc.), shown instead of a
    /// stale report. (SPEC §1)
    private(set) var leakMessage: String?
    /// The most recent recorded deep trace, carrying the `.trace` path to open in Instruments.
    private(set) var traceResult: DiagnosticResult?
    /// Why the last trace recording failed (commonly the debugger-entitlement task-port wall).
    private(set) var traceMessage: String?
    /// The most recent zombie-check result (findings from a relaunch under `NSZombieEnabled`),
    /// or `nil` until a check is run. (SPEC §1; PLAN slice 7)
    private(set) var zombieReport: DiagnosticResult?
    /// Why the last zombie check could not complete (couldn't relaunch the executable, etc.).
    private(set) var zombieMessage: String?
    /// Whether any on-demand deep diagnostic (leak check, trace recording, or zombie check) is
    /// in flight — drives the progress spinner shared by those actions.
    private(set) var isRunningDiagnostic = false

    var latest: MetricSample? { samples.last }
    /// Whether an on-demand measured-energy read is wired for this target. (SPEC §5)
    var canMeasureEnergy: Bool { energySource != nil }
    /// Whether a quick leak check (`leaks` CLI) is wired for this target. (SPEC §1; PLAN slice 6)
    var canCheckLeaks: Bool { leakChecker != nil && target != nil }
    /// Whether a deep trace recording (`xctrace`) is wired for this target. (PLAN slice 6)
    var canRecordTrace: Bool { traceRecorder != nil && target != nil }
    /// Whether a zombie check is wired for this target. Requires both a runner and an
    /// executable path to relaunch — zombies cannot attach to the running process, so without
    /// a path there is nothing to relaunch and the action is hidden. (SPEC §1; PLAN slice 7)
    var canCheckZombies: Bool { zombieRunner != nil && target?.executablePath != nil }

    private let source: MetricsSource
    private let networkSource: NetworkSource?
    private let energySource: EnergySource?
    private let leakChecker: DiagnosticRunner?
    private let traceRecorder: DiagnosticRunner?
    private let zombieRunner: DiagnosticRunner?
    private let target: Target?
    private let pid: Int32
    private let capacity: Int
    private let evaluateThresholds = EvaluateThresholds()
    private var previousReading: VitalsReading?
    private var previousNetworkReading: NetworkReading?

    /// `capacity` defaults to one hour of 1 Hz samples — the retention cap from SPEC §4.
    /// `networkSource`, `energySource`, and the diagnostic runners are optional: without them
    /// the corresponding signal/action is unavailable (the live estimate still rides each
    /// tick). The deep runners take the full `target` because they attach by it. (SPEC §3.1)
    init(
        source: MetricsSource,
        networkSource: NetworkSource? = nil,
        energySource: EnergySource? = nil,
        leakChecker: DiagnosticRunner? = nil,
        traceRecorder: DiagnosticRunner? = nil,
        zombieRunner: DiagnosticRunner? = nil,
        target: Target? = nil,
        pid: Int32,
        capacity: Int = 3600,
        thresholds: [Threshold] = Threshold.defaults
    ) {
        self.source = source
        self.networkSource = networkSource
        self.energySource = energySource
        self.leakChecker = leakChecker
        self.traceRecorder = traceRecorder
        self.zombieRunner = zombieRunner
        self.target = target
        self.pid = pid
        self.capacity = capacity
        self.thresholds = thresholds
    }

    /// One polling tick: read the target's vitals, derive a sample from the previous
    /// reading, attach the network throughput, and append it. The first tick only
    /// establishes a baseline (no delta yet). The libproc read is authoritative for
    /// liveness — its failure surfaces as an error and stops the tick; the network read is
    /// best-effort and never clobbers that error.
    func poll() async {
        do {
            let reading = try source.sample(pid: pid)
            let networkRate = await sampleNetworkRate()
            if let previousReading {
                let sample = MetricSample.derive(from: previousReading, to: reading)
                append(sample.withNetwork(networkRate))
            }
            previousReading = reading
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Read the network counters and derive a rate from the previous reading. Best-effort:
    /// no source, or a transient `nettop` failure, yields a zero rate rather than failing
    /// the whole tick. (PLAN slice 4)
    private func sampleNetworkRate() async -> NetworkRate {
        guard let networkSource else { return .zero }
        do {
            let reading = try await networkSource.sample(pid: pid)
            defer { previousNetworkReading = reading }
            guard let previousNetworkReading else { return .zero }
            return NetworkRate.derive(from: previousNetworkReading, to: reading)
        } catch {
            return .zero
        }
    }

    /// Take one on-demand measured-energy reading via `powermetrics`. This is the deep,
    /// privileged read (SPEC §1's deep-run mode) — distinct from the estimate on every tick.
    /// If the tool can't run (no root) the measurement degrades: `measuredEnergy` stays
    /// `nil` and `energyMessage` explains why, so the UI never fakes a measured figure.
    func measureEnergy() async {
        guard let energySource else { return }
        do {
            measuredEnergy = try await energySource.measuredEnergyImpact(pid: pid)
            energyMessage = nil
        } catch EnergyMeasurementError.unavailable {
            measuredEnergy = nil
            energyMessage = "Measured energy needs elevated privileges — showing the estimate."
        } catch {
            measuredEnergy = nil
            energyMessage = "Measured energy unavailable — showing the estimate."
        }
    }

    /// Run a quick leak check (`leaks <pid>`) on demand and store the findings. This is the
    /// fast attach path (SPEC §1's deep-run mode, light end): it scans malloc zones without the
    /// full task port. A failure surfaces as `leakMessage` rather than a stale report. (PLAN slice 6)
    func checkLeaks() async {
        await runDiagnostic(
            leakChecker, failureLabel: "Leak check",
            onSuccess: { self.leakReport = $0; self.leakMessage = nil },
            onFailure: { self.leakReport = nil; self.leakMessage = $0 }
        )
    }

    /// Record a deep Leaks trace via `xctrace` and store its `.trace` path for opening in
    /// Instruments. The deep attach needs the debugger entitlement; if it can't acquire the
    /// task port the failure is reported honestly via `traceMessage`. (SPEC §1, §5; PLAN slice 6)
    func recordLeakTrace() async {
        await runDiagnostic(
            traceRecorder, failureLabel: "Trace recording",
            onSuccess: { self.traceResult = $0; self.traceMessage = nil },
            onFailure: { self.traceResult = nil; self.traceMessage = $0 }
        )
    }

    /// Check for over-released objects by relaunching the target under `NSZombieEnabled` and
    /// storing any findings. Zombies cannot be detected on the running process — this starts a
    /// fresh instance (SPEC §1's relaunch-only constraint); a failure to relaunch surfaces as
    /// `zombieMessage` rather than a stale report. (PLAN slice 7)
    func checkZombies() async {
        await runDiagnostic(
            zombieRunner, failureLabel: "Zombie check",
            onSuccess: { self.zombieReport = $0; self.zombieMessage = nil },
            onFailure: { self.zombieReport = nil; self.zombieMessage = $0 }
        )
    }

    /// Run a deep diagnostic on the latched target behind the shared busy flag, routing its
    /// result or failure message to the caller's storage. The two leak actions differ only in
    /// which fields they write, so the run/guard/error shape lives here once. (Fowler: Extract
    /// Function + Parameterize Function)
    private func runDiagnostic(
        _ runner: DiagnosticRunner?,
        failureLabel: String,
        onSuccess: (DiagnosticResult) -> Void,
        onFailure: (String) -> Void
    ) async {
        guard let runner, let target else { return }
        isRunningDiagnostic = true
        defer { isRunningDiagnostic = false }
        do {
            onSuccess(try await runner.run(target, options: DiagnosticOptions()))
        } catch {
            onFailure("\(failureLabel) failed — \(diagnosticFailureReason(error))")
        }
    }

    /// Human-readable reason for a diagnostic failure, preferring the tool's own stderr.
    private func diagnosticFailureReason(_ error: Error) -> String {
        if case let DiagnosticError.toolFailed(_, message) = error, !message.isEmpty {
            return message
        }
        return error.localizedDescription
    }

    /// Override one signal's threshold value (per-target tuning) and re-evaluate the
    /// current window so the UI reflects the change immediately. (SPEC §3.3)
    func updateThreshold(_ signal: SignalKind, value: Double) {
        thresholds = thresholds.map { threshold in
            guard threshold.signal == signal else { return threshold }
            return Threshold(
                signal: signal,
                comparator: threshold.comparator,
                value: value,
                window: threshold.window
            )
        }
        refreshAlerts()
    }

    private func append(_ sample: MetricSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        refreshAlerts()
    }

    private func refreshAlerts() {
        alerts = evaluateThresholds(samples: samples, thresholds: thresholds)
    }
}
