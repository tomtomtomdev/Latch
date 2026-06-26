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

    init(target: Target) {
        self.target = target
        _model = State(initialValue: VitalsModel(source: LibprocMetricsSource(), pid: target.pid ?? -1))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                cpuChart
                memoryChart
            }
            .padding()
        }
        .navigationTitle(target.displayName)
        .task(id: target.id) { await pollLoop() }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            model.poll()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            if let pid = target.pid {
                stat("PID", "\(pid)")
            }
            stat("CPU", model.latest.map { String(format: "%.0f%%", $0.cpuPercent) } ?? "—")
            stat("Memory", model.latest.map { String(format: "%.1f MB", $0.physFootprintMegabytes) } ?? "—")
            stat("Threads", model.latest.map { "\($0.threadCount)" } ?? "—")
        }
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
