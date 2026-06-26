import SwiftUI
import LatchDomain

/// Slice 1: pick a same-UID local process to latch onto. A searchable sidebar of
/// discovered processes; selecting one shows it as the latched target. (PLAN slice 1)
struct ContentView: View {
    @State private var model: TargetPickerModel

    init(model: TargetPickerModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationSplitView {
            List(model.filteredTargets, selection: selectionBinding) { target in
                TargetRow(target: target).tag(target.id)
            }
            .searchable(text: $model.searchText, placement: .sidebar, prompt: "Filter processes")
            .navigationTitle("Processes")
            .overlay { discoveryError }
        } detail: {
            detail
        }
        .task { await model.load() }
    }

    @ViewBuilder private var discoveryError: some View {
        if let message = model.errorMessage {
            ContentUnavailableView(
                "Discovery failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    @ViewBuilder private var detail: some View {
        if let target = model.selected {
            VitalsView(target: target)
        } else {
            ContentUnavailableView(
                "No target latched",
                systemImage: "link",
                description: Text("Select a process to latch onto.")
            )
        }
    }

    private var selectionBinding: Binding<Target.ID?> {
        Binding(
            get: { model.selected?.id },
            set: { id in
                if let target = model.filteredTargets.first(where: { $0.id == id }) {
                    model.select(target)
                }
            }
        )
    }
}

private struct TargetRow: View {
    let target: Target

    var body: some View {
        HStack {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(target.displayName)
                if let pid = target.pid {
                    Text("pid \(pid)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    struct PreviewDiscovery: TargetDiscovery {
        func localProcesses() async throws -> [Target] {
            [
                Target(id: "1", kind: .localMac, pid: 1, displayName: "Safari"),
                Target(id: "2", kind: .localMac, pid: 2, displayName: "Xcode"),
            ]
        }
    }
    return ContentView(model: TargetPickerModel(discovery: PreviewDiscovery()))
}
