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
    /// The most recent hitch/hang check result (a `sample` of the main thread → stall
    /// findings), or `nil` until a check is run. (SPEC §3.3; PLAN slice 8)
    private(set) var hitchReport: DiagnosticResult?
    /// Why the last hitch check could not complete (target exited, etc.).
    private(set) var hitchMessage: String?
    /// The most recent recorded Time Profiler trace, carrying the `.trace` path to open in
    /// Instruments for the full main-thread analysis. (PLAN slice 8)
    private(set) var hitchTraceResult: DiagnosticResult?
    /// Why the last Time Profiler recording failed (commonly the debugger-entitlement wall).
    private(set) var hitchTraceMessage: String?
    /// Whether any on-demand deep diagnostic (leak check, trace recording, or zombie check) is
    /// in flight — drives the progress spinner shared by those actions.
    private(set) var isRunningDiagnostic = false
    /// The visible span of the timeline (30s/1m/5m). Trims `visibleSamples`; the full ring
    /// buffer is retained regardless. (SPEC §8; PLAN slice 11)
    var range: TimelineRange = .oneMinute
    /// Whether live sampling is frozen. A paused poll advances nothing; resuming rebaselines so
    /// the first post-resume sample isn't a bogus delta spanning the paused gap. (SPEC §8)
    private(set) var isPaused = false

    /// The right-panel inbox feed: live threshold hints + deep-run findings, newest first, capped.
    /// (SPEC §8; PLAN slice 12)
    private var detectionLog = DetectionLog()
    /// The detection whose diagnostic detail the right panel is showing, or `nil` for the inbox.
    private(set) var selectedDetectionID: Detection.ID?
    /// Cumulative count of appended samples (unbounded by the ring cap) — the "clock" that places
    /// a live hint's timeline marker. The Domain is clock-free, so at 1 Hz this sample index is the
    /// honest ordinate. (SPEC §4; PLAN slice 12)
    private var totalSampleCount = 0

    var latest: MetricSample? { samples.last }
    /// The trailing samples within the selected `range` — what the timeline actually draws.
    var visibleSamples: [MetricSample] { Array(samples.suffix(range.sampleCount)) }
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
    /// Whether a quick hitch/hang check (`sample` CLI) is wired for this target. (PLAN slice 8)
    var canCheckHitches: Bool { hitchRunner != nil && target != nil }
    /// Whether a deep Time Profiler trace recording (`xctrace`) is wired for this target. (PLAN slice 8)
    var canRecordHitchTrace: Bool { hitchTraceRecorder != nil && target != nil }

    private let source: MetricsSource
    private let networkSource: NetworkSource?
    private let energySource: EnergySource?
    private let leakChecker: DiagnosticRunner?
    private let traceRecorder: DiagnosticRunner?
    private let zombieRunner: DiagnosticRunner?
    private let hitchRunner: DiagnosticRunner?
    private let hitchTraceRecorder: DiagnosticRunner?
    /// The latched target, exposed so the shell's sidebar can label and group each stream.
    let target: Target?
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
        hitchRunner: DiagnosticRunner? = nil,
        hitchTraceRecorder: DiagnosticRunner? = nil,
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
        self.hitchRunner = hitchRunner
        self.hitchTraceRecorder = hitchTraceRecorder
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
        guard !isPaused else { return }
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
            onSuccess: { self.leakReport = $0; self.leakMessage = nil; self.detectionLog.addDeepRun($0) },
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
            onSuccess: { self.zombieReport = $0; self.zombieMessage = nil; self.detectionLog.addDeepRun($0) },
            onFailure: { self.zombieReport = nil; self.zombieMessage = $0 }
        )
    }

    /// Take a quick hitch/hang look by sampling the running target (`sample <pid>`) and storing
    /// any main-thread stall findings. This is the verified same-UID sampling path (SPEC §1's
    /// deep-run mode, light end); a failure surfaces as `hitchMessage` rather than a stale
    /// report. The stall verdict is an honest hint — the Time Profiler trace is ground truth.
    /// (PLAN slice 8)
    func checkHitches() async {
        await runDiagnostic(
            hitchRunner, failureLabel: "Hitch check",
            onSuccess: { self.hitchReport = $0; self.hitchMessage = nil; self.detectionLog.addDeepRun($0) },
            onFailure: { self.hitchReport = nil; self.hitchMessage = $0 }
        )
    }

    /// Record a deep Time Profiler trace via `xctrace` and store its `.trace` path for opening
    /// in Instruments. The deep attach needs the debugger entitlement; if it can't acquire the
    /// task port the failure is reported honestly via `hitchTraceMessage`. (SPEC §1, §5; PLAN slice 8)
    func recordHitchTrace() async {
        await runDiagnostic(
            hitchTraceRecorder, failureLabel: "Time Profiler recording",
            onSuccess: { self.hitchTraceResult = $0; self.hitchTraceMessage = nil },
            onFailure: { self.hitchTraceResult = nil; self.hitchTraceMessage = $0 }
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

    /// Freeze or resume live sampling. Pausing drops the baseline so the first poll after
    /// resume re-establishes it rather than deriving a delta across the whole paused gap. (SPEC §8)
    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused { previousReading = nil }
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
        totalSampleCount += 1
        refreshAlerts()
    }

    private func refreshAlerts() {
        alerts = evaluateThresholds(samples: samples, thresholds: thresholds)
        detectionLog.syncAlerts(alerts, sampleTick: totalSampleCount)
    }
}

// MARK: - At-a-glance summary

/// The compact readouts the sidebar dot and the menu-bar companion row bind to: overall health,
/// how many signals are firing, and a one-line vitals summary. Pure folds over the current alert
/// set and the latest sample — no new state. (SPEC §8; PLAN slices 11, 13)
extension VitalsModel {
    /// Overall health, folded from the active live alerts (critical dominates). (PLAN slice 11)
    var health: TargetHealth { TargetHealth.from(alerts: alerts) }

    /// How many signals are currently firing.
    var issueCount: Int { alerts.count }

    /// The health/issue label in the companion row, e.g. `Healthy` / `1 issue` / `3 issues`.
    var statusSummary: String {
        switch issueCount {
        case 0: "Healthy"
        case 1: "1 issue"
        default: "\(issueCount) issues"
        }
    }

    /// The compact vitals line, e.g. `CPU 61% · 540 MB · 12.0 MB/s`, or `—` before the first
    /// sample — an honest placeholder, never a fabricated zero. (SPEC §8)
    var vitalsLine: String {
        guard let sample = latest else { return "—" }
        return String(
            format: "CPU %.0f%% · %.0f MB · %.1f MB/s",
            sample.cpuPercent, sample.physFootprintMegabytes, sample.networkMegabytesPerSecond
        )
    }
}

// MARK: - Detection inbox

/// The right-panel inbox feed (SPEC §8; PLAN slice 12). The feed accumulates as `refreshAlerts`
/// and the deep-run checks push into `detectionLog`; this extension is the read/select surface the
/// inbox, detail, and timeline markers bind to. Same-file so it keeps `private` access to the log
/// and the sample "clock" while staying its own cohesive concern.
extension VitalsModel {
    /// The inbox feed (newest first).
    var detections: [Detection] { detectionLog.detections }

    /// The selected detection's detail, or `nil` when the inbox is showing.
    var selectedDetection: Detection? { detections.first { $0.id == selectedDetectionID } }

    /// Open a detection's diagnostic detail (from an inbox card or a timeline marker).
    func selectDetection(_ id: Detection.ID) {
        selectedDetectionID = id
    }

    /// Return from a diagnostic detail to the inbox.
    func clearSelectedDetection() {
        selectedDetectionID = nil
    }

    /// Horizontal position (0…1) of a detection's marker within the visible window, or `nil` when
    /// it has no tick (a deep run — inbox-only) or has scrolled out of the window.
    func markerFraction(for detection: Detection) -> Double? {
        guard let tick = detection.sampleTick else { return nil }
        let visible = visibleSamples.count
        guard visible > 0 else { return nil }
        let firstVisibleTick = totalSampleCount - visible + 1
        guard tick >= firstVisibleTick, tick <= totalSampleCount else { return nil }
        guard visible > 1 else { return 1 }
        return Double(tick - firstVisibleTick) / Double(visible - 1)
    }
}
