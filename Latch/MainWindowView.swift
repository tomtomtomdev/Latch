import SwiftUI
import LatchDomain
import LatchData

/// The main window shell (SPEC §8): toolbar over a three-column body — sidebar of attached
/// targets, center live timeline, right detection panel. It owns the `MainWindowModel`, drives
/// the ~1 Hz poll loop for the selected stream, and hosts the attach + settings surfaces. The
/// detection inbox (slice 12) and menu-bar companion (slice 13) build on this. (PLAN slice 11)
struct MainWindowView: View {
    @State private var model = MainWindowModel()
    @State private var showingAttach = false
    @State private var showingSettings = false

    private let discovery = LibprocTargetDiscovery(lister: LibprocProcessLister())

    var body: some View {
        VStack(spacing: 0) {
            if let selected = model.selected {
                MainToolbar(model: selected) { showingSettings = true }
            }
            HStack(spacing: 0) {
                SidebarView(model: model) { showingAttach = true }
                if let selected = model.selected {
                    TimelineView(model: selected).frame(maxWidth: .infinity, maxHeight: .infinity)
                    DetectionInboxView(model: selected)
                } else {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 640)
        .background(LatchTheme.window)
        .preferredColorScheme(.dark)
        .task(id: model.selected?.target?.id) { await pollSelected() }
        .sheet(isPresented: $showingAttach) {
            AttachSheet(picker: TargetPickerModel(discovery: discovery)) { target in
                model.attach(.live(for: target))
            }
        }
        .sheet(isPresented: $showingSettings) { settingsSheet }
    }

    @ViewBuilder private var settingsSheet: some View {
        if let selected = model.selected {
            VStack(spacing: 0) {
                HStack {
                    Text("Thresholds — \(selected.target?.displayName ?? "")").font(.headline)
                    Spacer()
                    Button("Done") { showingSettings = false }
                }
                .padding()
                Divider()
                ThresholdSettingsView(model: selected)
            }
            .frame(width: 380, height: 360)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No target latched", systemImage: "link")
        } description: {
            Text("Attach a same-UID process to stream its live vitals.")
        } actions: {
            Button("Attach process…") { showingAttach = true }
                .buttonStyle(.borderedProminent)
        }
        .background(LatchTheme.center)
    }

    /// Poll the selected stream at ~1 Hz. Re-runs whenever the selected target changes (the
    /// `.task(id:)` above keys on its id), so switching targets streams the newly-selected one.
    private func pollSelected() async {
        guard let stream = model.selected else { return }
        while !Task.isCancelled {
            await stream.poll()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
