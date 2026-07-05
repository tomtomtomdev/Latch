import SwiftUI
import LatchDomain

/// The right panel — interim. Slice 12 replaces this with the provenance-tagged detection inbox
/// + diagnostic detail. Until then it keeps the shipped functionality reachable: the live
/// threshold alerts, the on-demand energy measurement, and the deep-run diagnostics (leaks,
/// hitches, zombies). Honestly labelled as a placeholder. (SPEC §8; PLAN slices 11–12)
struct DetectionsPanelView: View {
    let model: VitalsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LatchTheme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    alertsSection
                    energySection
                    DeepDiagnosticsView(model: model)
                }
                .padding(16)
            }
        }
        .frame(width: 362)
        .background(LatchTheme.rightPanel)
        .overlay(alignment: .leading) { Rectangle().fill(LatchTheme.hairline).frame(width: 1) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("DETECTIONS").font(.system(size: 13, weight: .bold)).kerning(0.4)
                    .foregroundStyle(LatchTheme.textPrimary)
                Spacer()
                Text("\(model.alerts.count) active").font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(LatchTheme.textFaint)
            }
            Text("Interim panel — the detection inbox arrives in the next update.")
                .font(.system(size: 10)).foregroundStyle(LatchTheme.textFaint)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    /// Live threshold alerts (§3.3). These become inbox cards in slice 12; shown plainly for now.
    @ViewBuilder private var alertsSection: some View {
        if model.alerts.isEmpty {
            Label("No live detections", systemImage: "checkmark.seal")
                .font(.callout).foregroundStyle(.green)
        } else {
            ForEach(model.alerts) { alert in
                Label(alertMessage(alert), systemImage: "exclamationmark.octagon.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.red)
            }
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

    /// Energy: the always-available watts estimate plus an on-demand measured `powermetrics`
    /// impact, labelled distinctly, degrading honestly when unprivileged. (SPEC §3.3, §5)
    @ViewBuilder private var energySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy").font(.headline)
            HStack(spacing: 24) {
                stat("Estimate", model.latest.map { String(format: "%.2f W", $0.energyWatts) } ?? "—")
                if let measured = model.measuredEnergy {
                    stat("Measured (impact)", String(format: "%.1f", measured))
                }
                if model.canMeasureEnergy {
                    Button("Measure energy", systemImage: "bolt.fill") {
                        Task { await model.measureEnergy() }
                    }
                }
            }
            Text("Estimate from rusage energy (no privileges). Measured energy uses powermetrics "
                + "and needs root.")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.energyMessage {
                Label(message, systemImage: "lock.fill").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }
}
