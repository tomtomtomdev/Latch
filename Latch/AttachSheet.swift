import SwiftUI
import LatchDomain

/// The `+ Attach process…` sheet: a searchable list of same-UID local processes (via the
/// slice-1 `TargetPickerModel`). Picking one builds its live stream and attaches it to the main
/// window. Connected iOS devices are surfaced in a separate section with their eligibility verdict,
/// but are not yet attachable — on-device app enumeration is deferred (SPEC §1, no fake attach).
/// (SPEC §1, §3.2; PLAN slices 9, 11)
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
            VStack(spacing: 0) {
                filterField
                Divider()
                List {
                    Section("Processes") {
                        ForEach(picker.filteredTargets) { target in
                            processRow(target)
                        }
                    }
                    if !picker.devices.isEmpty {
                        Section("iOS devices") {
                            ForEach(picker.devices) { device in
                                DeviceRow(device: device)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A plain filter field rather than `.searchable`: on macOS `.searchable` bare on a `List`
    /// in a fixed-frame sheet (no navigation container) drives an unbounded "Update Constraints
    /// in Window" loop that crashes with `NSGenericException`. A `TextField` filters the same
    /// `picker.searchText` without that layout feedback.
    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter processes", text: $picker.searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func processRow(_ target: Target) -> some View {
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
}

/// One connected iOS device, shown with its honest eligibility verdict. Not selectable: on-device
/// app enumeration is deferred (SPEC §1 — no fake attach), so an eligible device is surfaced but
/// not yet attachable, and an ineligible one shows the reason it can't be profiled. (PLAN slice 9)
private struct DeviceRow: View {
    let device: Device

    private var isEligible: Bool { device.profilingEligibility.isEligible }

    private var statusMessage: String {
        switch device.profilingEligibility {
        case .eligible:
            "Eligible · on-device app profiling isn’t available yet."
        case .ineligible(let reason):
            reason.message
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isEligible ? "iphone" : "iphone.slash")
                .foregroundStyle(isEligible ? .teal : .orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                    if let osVersion = device.osVersion {
                        Text("iOS \(osVersion)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
