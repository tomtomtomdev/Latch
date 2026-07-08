import SwiftUI
import LatchDomain

/// The window toolbar: the Latch mark + latched target title, the five live metric chips (which
/// mirror the timeline lanes), the `30s/1m/5m` range control, Pause/Resume, and the settings gear.
/// Chips and range read/drive the selected stream directly. (SPEC §8; PLAN slice 11)
struct MainToolbar: View {
    @Bindable var model: VitalsModel
    var onExport: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            mark
            titleBlock
            chips.frame(maxWidth: .infinity)
            rangeControl
            pauseButton
            exportButton
            settingsButton
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(LinearGradient(
            colors: [Color(hex: "#2f2f35"), Color(hex: "#26262b")],
            startPoint: .top, endPoint: .bottom
        ))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.45)).frame(height: 1) }
    }

    private var mark: some View {
        Image(systemName: "link")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(LatchTheme.teal)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.target?.displayName ?? "No target")
                .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            HStack(spacing: 5) {
                Circle().fill(LatchTheme.healthy).frame(width: 7, height: 7)
                Text(model.isPaused ? "Paused" : "Latched · sampling")
                    .font(.system(size: 11)).foregroundStyle(LatchTheme.textMuted)
            }
        }
        .frame(minWidth: 172, alignment: .leading)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(LaneKind.allCases) { lane in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(lane.color).frame(width: 8, height: 8)
                    Text(lane.chipLabel).font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(LatchTheme.textMuted)
                    Text(lane.formattedValue(from: model.latest))
                        .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(LatchTheme.textPrimary)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(LatchTheme.chipFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LatchTheme.hairline))
            }
        }
    }

    private var rangeControl: some View {
        HStack(spacing: 2) {
            ForEach(TimelineRange.allCases) { range in
                Button { model.range = range } label: {
                    Text(range.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.range == range ? .white : LatchTheme.textMuted)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(
                            model.range == range ? Color.white.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LatchTheme.hairline))
    }

    private var pauseButton: some View {
        Button { model.setPaused(!model.isPaused) } label: {
            HStack(spacing: 6) {
                Circle().fill(model.isPaused ? LatchTheme.warning : LatchTheme.healthy)
                    .frame(width: 7, height: 7)
                Text(model.isPaused ? "Resume" : "Pause")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.isPaused ? Color(hex: "#FFB340") : LatchTheme.textSecondary)
            }
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(
                model.isPaused ? LatchTheme.warning.opacity(0.13) : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                model.isPaused ? LatchTheme.warning.opacity(0.45) : Color.white.opacity(0.1)
            ))
        }
        .buttonStyle(.plain)
    }

    private var exportButton: some View {
        Button(action: onExport) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15)).foregroundStyle(LatchTheme.textSecondary)
                .frame(width: 32, height: 30)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LatchTheme.hairline))
        }
        .buttonStyle(.plain)
        .help("Export session report (JSON + Markdown)")
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 15)).foregroundStyle(LatchTheme.textSecondary)
                .frame(width: 32, height: 30)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LatchTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}
