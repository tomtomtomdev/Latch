import SwiftUI
import LatchDomain

/// The right panel (SPEC §8): the **detection inbox** by default, or a **diagnostic detail** when
/// a detection is selected (from a card or a timeline marker). The inbox merges live threshold
/// hints and deep-run findings into one provenance-tagged feed; the detail shows the deep run's
/// call tree + stack trace and the on-demand `Symbolicate` / `Copy trace` actions. (PLAN slice 12)
struct DetectionInboxView: View {
    let model: VitalsModel

    var body: some View {
        VStack(spacing: 0) {
            if let detection = model.selectedDetection {
                DiagnosticDetailView(model: model, detection: detection)
            } else {
                DetectionInbox(model: model)
            }
        }
        .frame(width: 362)
        .background(LatchTheme.rightPanel)
        .overlay(alignment: .leading) { Rectangle().fill(LatchTheme.hairline).frame(width: 1) }
    }
}

/// The default inbox state: header (count + severity filter), the deep-run launcher + honest run
/// status, then the newest-first card feed (or the "0 detections" empty state). (SPEC §8)
private struct DetectionInbox: View {
    let model: VitalsModel
    @State private var criticalOnly = false

    private var feed: [Detection] {
        criticalOnly ? model.detections.filter { $0.severity == .critical } : model.detections
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LatchTheme.hairline)
            DiagnosticRunBar(model: model)
            Divider().overlay(LatchTheme.hairline)
            if feed.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(feed) { detection in
                            DetectionCard(detection: detection, isSelected: false)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selectDetection(detection.id) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("DETECTIONS").font(.system(size: 13, weight: .bold)).kerning(0.4)
                .foregroundStyle(LatchTheme.textPrimary)
            Text("\(model.detections.count) total").font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(LatchTheme.textFaint)
            Spacer()
            filterChip("All", active: !criticalOnly) { criticalOnly = false }
            filterChip("Critical", active: criticalOnly) { criticalOnly = true }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private func filterChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? LatchTheme.textSecondary : LatchTheme.textMuted)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(active ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 26)).foregroundStyle(LatchTheme.healthy)
            Text("0 detections").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LatchTheme.textSecondary)
            Text("Live threshold hints and deep-run findings appear here.")
                .font(.system(size: 11)).foregroundStyle(LatchTheme.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// One inbox card: a severity bar, title + severity label, subtitle, and a footer that states the
/// lane and the **provenance** (live hint vs deep run + adapter) — never conflating the two. (SPEC §8)
struct DetectionCard: View {
    let detection: Detection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(detection.severity.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(detection.title).font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "#f2f2f4")).lineLimit(1)
                    Spacer()
                    Text(detection.severity.rawValue.capitalized)
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(detection.severity.color)
                }
                Text(detection.subtitle).font(.system(size: 11))
                    .foregroundStyle(LatchTheme.textMuted).lineLimit(1)
                HStack(spacing: 8) {
                    if let lane = detection.lane { laneChip(lane) }
                    Text(detection.provenance.label).font(.system(size: 10.5))
                        .foregroundStyle(LatchTheme.textFaint).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .background(isSelected ? Color.white.opacity(0.06) : Color.white.opacity(0.02),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            isSelected ? detection.severity.color.opacity(0.4) : Color.white.opacity(0.07)
        ))
    }

    private func laneChip(_ lane: LaneKind) -> some View {
        Text(lane.title).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(lane.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(lane.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5))
    }
}
