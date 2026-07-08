import SwiftUI
import AppKit
import LatchDomain

/// The diagnostic detail for one selected detection (SPEC §8): a meta grid, the description, the
/// call tree + stack trace **from the deep run**, suggested fixes, and the `Symbolicate` / `Copy
/// trace` actions. Honesty: a **live hint** carries no call tree/stack — those sections say so and
/// `Symbolicate` is the on-demand action to run the real deep diagnostic; a live hint never
/// masquerades as a symbolicated deep finding. (SPEC §1, §8; PLAN slice 12)
struct DiagnosticDetailView: View {
    let model: VitalsModel
    let detection: Detection

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LatchTheme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    titleBlock
                    metaGrid
                    Text(detection.detail).font(.system(size: 12.5)).lineSpacing(3)
                        .foregroundStyle(Color(hex: "#bcbcc2"))
                    callTreeSection
                    stackTraceSection
                    suggestedFixSection
                    actions
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { model.clearSelectedDetection() } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LatchTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(LatchTheme.hairline))
            }
            .buttonStyle(.plain)
            Text("DIAGNOSTIC DETAIL").font(.system(size: 11, weight: .bold)).kerning(0.5)
                .foregroundStyle(LatchTheme.textMuted)
            Spacer()
            Text(detection.severity.rawValue.capitalized)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(detection.severity.color)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(detection.severity.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detection.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Text(detection.subtitle).font(.system(size: 12)).foregroundStyle(Color(hex: "#9b9ba0"))
        }
    }

    private var metaGrid: some View {
        let laneColor = detection.lane?.color ?? LatchTheme.textSecondary
        return LazyVGrid(columns: [GridItem(spacing: 1), GridItem(spacing: 1)], spacing: 1) {
            metaCell("TARGET", model.target?.displayName ?? "—", LatchTheme.textSecondary)
            metaCell("PROVENANCE", provenanceMode, LatchTheme.textSecondary)
            metaCell(detection.metricLabel, detection.metricValue, laneColor)
            metaCell("LANE", detection.lane?.title ?? "—", laneColor)
        }
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.07)))
    }

    private var provenanceMode: String {
        detection.provenance.mode == .livePoll ? "Live hint" : "Deep run"
    }

    private func metaCell(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9.5, weight: .bold)).kerning(0.4)
                .foregroundStyle(LatchTheme.textFaint)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(valueColor).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Color(hex: "#1f1f24"))
    }

    @ViewBuilder private var callTreeSection: some View {
        sectionHeader("CALL TREE · heaviest stack")
        if detection.callTree.isEmpty {
            emptyNote(callTreeNote)
        } else {
            VStack(spacing: 0) {
                ForEach(detection.callTree) { row in callTreeRow(row) }
            }
            .background(Color(hex: "#0f0f12"), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.07)))
        }
    }

    private func callTreeRow(_ row: CallTreeRow) -> some View {
        HStack {
            Text(row.name).font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color(hex: "#d6d6da")).lineLimit(1)
                .padding(.leading, CGFloat(row.depth) * 12)
            Spacer()
            if let pct = row.weightPercent {
                Text(String(format: "%.0f%%", pct)).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: "#9b9ba0"))
            }
        }
        .padding(.horizontal, 11).frame(height: 25)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1) }
    }

    private var callTreeNote: String {
        if detection.provenance.mode == .livePoll {
            return "No call tree — this is a live threshold hint. Symbolicate to run a deep diagnostic."
        }
        return detection.tracePath == nil
            ? "No call tree captured by this run."
            : "Weighted call tree is in the recorded .trace — open it in Instruments."
    }

    @ViewBuilder private var stackTraceSection: some View {
        sectionHeader("STACK TRACE")
        if detection.stackTrace.isEmpty {
            emptyNote(stackTraceNote)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(detection.stackTrace.enumerated()), id: \.offset) { _, frame in
                        Text(frame).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#9ea0a6"))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .background(Color(hex: "#0f0f12"), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.07)))
        }
    }

    private var stackTraceNote: String {
        if detection.provenance.mode == .livePoll {
            return "No stack — a live hint samples counters, not stacks. Symbolicate for a deep run."
        }
        return "No backtrace — relaunch the target with MallocStackLogging=1 to capture one."
    }

    @ViewBuilder private var suggestedFixSection: some View {
        if !detection.suggestedFixes.isEmpty {
            sectionHeader("SUGGESTED FIX")
            ForEach(Array(detection.suggestedFixes.enumerated()), id: \.offset) { _, fix in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                        .foregroundStyle(LatchTheme.healthy)
                    Text(fix).font(.system(size: 12)).foregroundStyle(Color(hex: "#cfd6d0"))
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(LatchTheme.healthy.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LatchTheme.healthy.opacity(0.18)))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let symbolicate {
                Button(symbolicate.label) { symbolicate.run() }
                    .buttonStyle(.borderedProminent).tint(LatchTheme.systemBlue)
                    .disabled(model.isRunningDiagnostic)
            }
            Button("Copy trace") { copyTrace() }
                .buttonStyle(.bordered)
                .disabled(detection.tracePath == nil && detection.stackTrace.isEmpty)
        }
    }

    /// The on-demand symbolication action for a **live hint**: run the deep diagnostic that would
    /// produce a symbolicated origin, when one is wired. A deep-run detection is already the deep
    /// output, so it offers none. (SPEC §8 — symbolication is the on-demand action)
    private var symbolicate: (label: String, run: () -> Void)? {
        guard detection.provenance.mode == .livePoll else { return nil }
        switch detection.signal {
        case .memoryLeak where model.canCheckLeaks:
            return ("Symbolicate (Leak Check)", { Task { await model.checkLeaks() } })
        case .cpuSpike, .hitch:
            guard model.canCheckHitches else { return nil }
            return ("Symbolicate (sample)", { Task { await model.checkHitches() } })
        default:
            return nil
        }
    }

    private func copyTrace() {
        let text = detection.tracePath ?? detection.stackTrace.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 10.5, weight: .bold)).kerning(0.6)
            .foregroundStyle(LatchTheme.textFaint)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(LatchTheme.textFaint)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#0f0f12"), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.07)))
    }
}
