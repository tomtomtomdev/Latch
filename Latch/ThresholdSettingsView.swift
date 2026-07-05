import SwiftUI
import LatchDomain

/// Per-target threshold tuning for the live signals. Edits route through
/// `VitalsModel.updateThreshold`, which re-evaluates the current window immediately. The
/// defaults are starting points, not science (SPEC §3.3). Presented from the toolbar gear.
/// (PLAN slice 3; moved out of the interim dashboard for the slice-11 shell)
struct ThresholdSettingsView: View {
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
