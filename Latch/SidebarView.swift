import SwiftUI
import LatchDomain

/// The attached-targets sidebar: a header with the count, one selectable row per attached
/// target (icon, name, device subtitle, health dot, issue badge), and the `+ Attach process…`
/// footer that opens the picker. Selecting a row swaps the streamed target. (SPEC §8; PLAN slice 11)
struct SidebarView: View {
    let model: MainWindowModel
    var onAttach: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.streams.enumerated()), id: \.offset) { index, stream in
                        TargetRow(stream: stream, isSelected: index == model.selectedIndex)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(index) }
                    }
                }
            }
            Spacer(minLength: 0)
            attachButton
        }
        .frame(width: 222)
        .background(LatchTheme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(LatchTheme.hairline).frame(width: 1) }
    }

    private var header: some View {
        HStack {
            Text("ATTACHED TARGETS")
                .font(.system(size: 10.5, weight: .bold)).kerning(1)
                .foregroundStyle(LatchTheme.textFaint)
            Spacer()
            Text("\(model.streams.count)").font(.system(size: 11)).foregroundStyle(LatchTheme.textFaint)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
    }

    private var attachButton: some View {
        Button(action: onAttach) {
            Text("+ Attach process…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LatchTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .padding(8)
    }
}

/// One sidebar row. Health and issue count fold from the target's live alerts. (SPEC §8)
private struct TargetRow: View {
    let stream: VitalsModel
    let isSelected: Bool

    private var health: TargetHealth { .from(alerts: stream.alerts) }
    private var issues: Int { stream.alerts.count }
    private var name: String { stream.target?.displayName ?? "Unknown" }
    private var subtitle: String {
        guard let target = stream.target else { return "" }
        if let pid = target.pid { return "This Mac · pid \(pid)" }
        return target.kind == .iOSDevice ? "iOS device" : "This Mac"
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(LatchTheme.textPrimary).lineLimit(1)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(LatchTheme.textFaint).lineLimit(1)
            }
            Spacer()
            statusStack
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(isSelected ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(LatchTheme.teal).frame(width: 2) }
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
    }

    private var icon: some View {
        let colors = stream.target?.kind == .iOSDevice
            ? [Color(hex: "#2DD4BF"), Color(hex: "#0A84FF")]
            : [Color(hex: "#8E8E93"), Color(hex: "#48484A")]
        return RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 30, height: 30)
            .overlay(
                Text(String(name.prefix(1)))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            )
    }

    private var statusStack: some View {
        HStack(spacing: 6) {
            Circle().fill(health.color).frame(width: 8, height: 8)
            if issues > 0 {
                Text("\(issues)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(minWidth: 16).padding(.horizontal, 2)
                    .background(health.color, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}
