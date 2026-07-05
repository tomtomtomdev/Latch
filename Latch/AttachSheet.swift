import SwiftUI
import LatchDomain

/// The `+ Attach process…` sheet: a searchable list of same-UID local processes (via the
/// slice-1 `TargetPickerModel`). Picking one builds its live stream and attaches it to the main
/// window. iOS device targets surface here once on-device enumeration lands (slice 9 deferral).
/// (SPEC §3.2; PLAN slice 11)
struct AttachSheet: View {
    @State private var picker: TargetPickerModel
    var onPick: (Target) -> Void
    @Environment(\.dismiss) private var dismiss

    init(picker: TargetPickerModel, onPick: @escaping (Target) -> Void) {
        _picker = State(initialValue: picker)
        self.onPick = onPick
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Attach to a process").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            Divider()
            content
        }
        .frame(width: 460, height: 520)
        .task { await picker.load() }
    }

    @ViewBuilder private var content: some View {
        if let message = picker.errorMessage {
            ContentUnavailableView("Discovery failed", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        } else {
            List(picker.filteredTargets) { target in
                Button {
                    onPick(target)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "app.dashed").foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(target.displayName)
                            if let pid = target.pid {
                                Text("pid \(pid)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $picker.searchText, prompt: "Filter processes")
        }
    }
}
