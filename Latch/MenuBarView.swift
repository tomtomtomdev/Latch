import SwiftUI
import LatchDomain

/// The menu-bar companion dropdown (SPEC §8; PLAN slice 13): a glanceable panel over the whole
/// fleet — a header count, one row per attached target (icon · vitals line · health/issue status),
/// the recent detections across targets, and a `Pause all` / `Resume all` + `Open Latch` footer.
/// It binds to the shared `MainWindowModel`; `onOpenLatch` bridges the AppKit activation so the
/// view itself stays free of `NSApp`. (design handoff "Menu-bar companion dropdown")
struct MenuBarView: View {
    let model: MainWindowModel
    var onOpenLatch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LatchTheme.hairline)
            if model.streams.isEmpty {
                emptyState
            } else {
                targetRows
                recentDetections
            }
            Divider().overlay(LatchTheme.hairline)
            footer
        }
        .frame(width: 346)
        .background(LatchTheme.rightPanel)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LatchTheme.teal)
            VStack(alignment: .leading, spacing: 1) {
                Text("Latch").font(.system(size: 13.5, weight: .bold)).foregroundStyle(.white)
                Text(model.monitoringSummary)
                    .font(.system(size: 11)).foregroundStyle(LatchTheme.textMuted)
            }
            Spacer()
            Circle().fill(LatchTheme.healthy).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - Target rows

    private var targetRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.streams.enumerated()), id: \.offset) { _, stream in
                CompanionRow(stream: stream)
            }
        }
        .padding(6)
    }

    // MARK: - Recent detections

    @ViewBuilder private var recentDetections: some View {
        let recent = model.recentDetections
        if !recent.isEmpty {
            Divider().overlay(LatchTheme.hairline)
            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT DETECTIONS")
                    .font(.system(size: 9.5, weight: .bold)).kerning(0.6)
                    .foregroundStyle(LatchTheme.textFaint)
                ForEach(recent) { detection in
                    HStack(spacing: 8) {
                        Circle().fill(detection.severity.color).frame(width: 6, height: 6)
                        Text(detection.title)
                            .font(.system(size: 12)).foregroundStyle(LatchTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(detection.provenance.mode == .livePoll ? "live" : "deep")
                            .font(.system(size: 10.5)).foregroundStyle(LatchTheme.textFaint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        Text("No targets attached")
            .font(.system(size: 12)).foregroundStyle(LatchTheme.textMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 22)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(model.allPaused ? "Resume all" : "Pause all") {
                if model.allPaused { model.resumeAll() } else { model.pauseAll() }
            }
            .buttonStyle(SecondaryButton())
            .disabled(model.streams.isEmpty)

            Button("Open Latch", action: onOpenLatch)
                .buttonStyle(PrimaryButton())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

/// One companion row: app icon initial, name, the compact vitals line, and the health dot + issue
/// label — all in the health color. Reads the shared per-target `VitalsModel` accessors. (SPEC §8)
private struct CompanionRow: View {
    let stream: VitalsModel

    private var name: String { stream.target?.displayName ?? "Unknown" }

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(hex: "#8E8E93"), Color(hex: "#48484A")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay(Text(String(name.prefix(1)))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(LatchTheme.textPrimary).lineLimit(1)
                Text(stream.vitalsLine).font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(LatchTheme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                Circle().fill(stream.health.color).frame(width: 7, height: 7)
                Text(stream.statusSummary)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(stream.health.color)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
    }
}

// MARK: - Button styles (handoff footer)

private struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium)).foregroundStyle(LatchTheme.textSecondary)
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.05),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LatchTheme.hairline))
    }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: "#04201b"))
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(LatchTheme.teal.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: 8))
    }
}
