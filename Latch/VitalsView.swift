import SwiftUI
import Charts
import LatchDomain
import LatchData

/// Live vitals dashboard for the latched target: 1 Hz line charts of CPU% and memory
/// footprint, plus the current thread count. Polling runs for the lifetime of the view
/// via `.task`, which SwiftUI cancels on disappear. (PLAN slice 2)
struct VitalsView: View {
    let target: Target
    @State private var model: VitalsModel
    @State private var showingSettings = false

    init(target: Target) {
        self.target = target
        let runner = ProcessCommandRunner()
        _model = State(initialValue: VitalsModel(
            source: LibprocMetricsSource(),
            networkSource: NettopMetricsSource(commandRunner: runner),
            energySource: PowermetricsSource(commandRunner: runner),
            leakChecker: LeaksCLIRunner(commandRunner: runner),
            traceRecorder: XctraceDiagnosticRunner(
                commandRunner: runner,
                outputDirectory: FileManager.default.temporaryDirectory.path
            ),
            zombieRunner: ZombieDiagnosticRunner(commandRunner: runner),
            target: target,
            pid: target.pid ?? -1
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                signalPills
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                alertBanners
                cpuChart
                memoryChart
                networkChart
                energySection
                DeepDiagnosticsView(model: model)
            }
            .padding()
        }
        .navigationTitle(target.displayName)
        .toolbar {
            Button("Thresholds", systemImage: "slider.horizontal.3") { showingSettings = true }
                .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                    ThresholdSettingsView(model: model).frame(width: 320)
                }
        }
        .task(id: target.id) { await pollLoop() }
    }

    private var signalPills: some View {
        HStack(spacing: 8) {
            ForEach(SignalKind.allCases, id: \.self) { signal in
                SignalPill(title: signal.title, status: status(for: signal))
            }
        }
    }

    private func status(for signal: SignalKind) -> SignalStatus {
        guard signal.hasLiveIndicator else { return .unavailable }
        return model.alerts.contains { $0.signal == signal } ? .alerting : .ok
    }

    @ViewBuilder private var alertBanners: some View {
        ForEach(model.alerts) { alert in
            Label(alertMessage(alert), systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout.weight(.medium))
        }
    }

    private func alertMessage(_ alert: LatchDomain.Alert) -> String {
        switch alert.signal {
        case .cpuSpike:
            return String(format: "CPU spike — %.0f%% of one core, sustained", alert.sample.cpuPercent)
        case .memoryLeak:
            let mb = alert.sample.physFootprintMegabytes
            return String(format: "Possible leak — footprint rising (%.1f MB)", mb)
        case .networkIO:
            let mbps = alert.sample.networkMegabytesPerSecond
            return String(format: "High network I/O — %.1f MB/s, sustained", mbps)
        case .battery:
            return String(format: "High energy use — %.1f W estimated, sustained", alert.sample.energyWatts)
        default:
            return "\(alert.signal.title) threshold breached"
        }
    }

    /// Energy: the always-available estimate (watts, from `ri_energy_nj`) plus an on-demand
    /// measured reading via `powermetrics`. The two are labelled distinctly — estimate vs
    /// measured — and a declined/unavailable privileged read degrades honestly. (SPEC §3.3, §5)
    @ViewBuilder private var energySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy").font(.headline)
            HStack(spacing: 24) {
                stat("Estimate", latest { String(format: "%.2f W", $0.energyWatts) })
                if let measured = model.measuredEnergy {
                    stat("Measured (impact)", String(format: "%.1f", measured))
                }
                if model.canMeasureEnergy {
                    Button("Measure energy", systemImage: "bolt.fill") {
                        Task { await model.measureEnergy() }
                    }
                }
            }
            Text("Estimate from rusage energy (no privileges). "
                + "Measured energy uses powermetrics and needs root.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = model.energyMessage {
                Label(message, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await model.poll()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            if let pid = target.pid {
                stat("PID", "\(pid)")
            }
            stat("CPU", latest { String(format: "%.0f%%", $0.cpuPercent) })
            stat("Memory", latest { String(format: "%.1f MB", $0.physFootprintMegabytes) })
            stat("Threads", latest { "\($0.threadCount)" })
            stat("Network", latest { String(format: "%.2f MB/s", $0.networkMegabytesPerSecond) })
        }
    }

    /// Format the latest sample, or an em-dash when no sample has been polled yet.
    private func latest(_ format: (MetricSample) -> String) -> String {
        model.latest.map(format) ?? "—"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }

    private var cpuChart: some View {
        lineChart(title: "CPU — % of one core", color: .blue) { $0.cpuPercent }
    }

    private var memoryChart: some View {
        lineChart(title: "Memory — footprint (MB)", color: .green) { $0.physFootprintMegabytes }
    }

    private var networkChart: some View {
        lineChart(title: "Network — throughput (MB/s)", color: .purple) { $0.networkMegabytesPerSecond }
    }

    private func lineChart(
        title: String,
        color: Color,
        value: @escaping (MetricSample) -> Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart(indexedSamples, id: \.index) { item in
                LineMark(x: .value("Sample", item.index), y: .value(title, value(item.sample)))
                    .foregroundStyle(color)
            }
            .frame(height: 160)
        }
    }

    private var indexedSamples: [(index: Int, sample: MetricSample)] {
        Array(model.samples.enumerated()).map { (index: $0.offset, sample: $0.element) }
    }
}

/// A compact status chip for one signal: green when monitored and within limits, red on
/// an active alert, grey when the signal has no live indicator yet. (SPEC §1)
private struct SignalPill: View {
    let title: String
    let status: SignalStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(title).font(.caption)
            Text(status.label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }
}

/// Per-target threshold tuning for the live signals. Edits route through
/// `VitalsModel.updateThreshold`, which re-evaluates the current window immediately. The
/// defaults are starting points, not science (SPEC §3.3). (PLAN slice 3)
private struct ThresholdSettingsView: View {
    @Bindable var model: VitalsModel

    var body: some View {
        Form {
            Section("Alert thresholds") {
                ForEach(model.thresholds) { threshold in
                    if threshold.signal.hasLiveIndicator {
                        thresholdStepper(threshold)
                    }
                }
            }
            Text("Defaults are starting points — tune them to this target.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func thresholdStepper(_ threshold: Threshold) -> some View {
        let binding = Binding(
            get: { threshold.value },
            set: { model.updateThreshold(threshold.signal, value: $0) }
        )
        return Stepper(value: binding, in: range(for: threshold.signal), step: step(for: threshold.signal)) {
            HStack {
                Text(label(for: threshold.signal))
                Spacer()
                Text(String(format: "%.0f %@", threshold.value, unit(for: threshold.signal)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(for signal: SignalKind) -> String {
        switch signal {
        case .cpuSpike: "CPU spike above"
        case .memoryLeak: "Footprint rising over"
        case .networkIO: "Network I/O above"
        case .battery: "Energy estimate above"
        default: signal.title
        }
    }

    private func unit(for signal: SignalKind) -> String {
        switch signal {
        case .cpuSpike: "% core"
        case .memoryLeak: "MB/min"
        case .networkIO: "MB/s"
        case .battery: "W"
        default: ""
        }
    }

    private func range(for signal: SignalKind) -> ClosedRange<Double> {
        switch signal {
        case .cpuSpike: 10...400
        case .memoryLeak: 1...100
        case .networkIO: 1...100
        case .battery: 1...100
        default: 0...100
        }
    }

    private func step(for signal: SignalKind) -> Double {
        signal == .cpuSpike ? 5 : 1
    }
}
