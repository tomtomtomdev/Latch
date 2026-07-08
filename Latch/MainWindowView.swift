import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LatchDomain
import LatchData

/// The main window shell (SPEC §8): toolbar over a three-column body — sidebar of attached
/// targets, center live timeline, right detection panel. It owns the `MainWindowModel`, drives
/// the ~1 Hz poll loop for the selected stream, and hosts the attach + settings surfaces. The
/// detection inbox (slice 12) and menu-bar companion (slice 13) build on this. (PLAN slice 11)
struct MainWindowView: View {
    /// Injected by `LatchApp` so the menu-bar companion shares the same fleet. (PLAN slice 13)
    let model: MainWindowModel
    @State private var showingAttach = false
    @State private var showingSettings = false

    /// Local same-UID processes (libproc) fused with connected iOS devices (devicectl), so the
    /// attach sheet lists both. Device rows are informational until on-device app enumeration
    /// lands (SPEC §1 — no fake attach). (PLAN slices 1, 9)
    private let discovery = CompositeTargetDiscovery([
        LibprocTargetDiscovery(lister: LibprocProcessLister()),
        DevicectlTargetDiscovery(commandRunner: ProcessCommandRunner()),
    ])

    var body: some View {
        VStack(spacing: 0) {
            if let selected = model.selected {
                MainToolbar(model: selected, onExport: { exportReport(for: selected) }) {
                    showingSettings = true
                }
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
        .task(id: model.streams.count) { await pollFleet() }
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

    /// Export the selected stream's session as a JSON bundle + Markdown summary. The report is
    /// assembled by the tested `VitalsModel.sessionReport()` seam; this humble part just runs the
    /// `NSSavePanel` and hands the chosen URL to `ReportExporter`. A failed write surfaces in an
    /// alert rather than silently dropping the report. (SPEC §4, §8; PLAN slice 10)
    private func exportReport(for stream: VitalsModel) {
        guard let report = stream.sessionReport() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(report.target.displayName)-session"
        panel.message = "Exports a JSON bundle plus a Markdown summary sidecar."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ReportExporter().write(report, to: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t export the session report."
            alert.runModal()
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

    /// Poll every attached stream at ~1 Hz. Re-runs whenever a target is attached (the `.task(id:)`
    /// above keys on the stream count), so the menu-bar companion glances at live health across the
    /// whole fleet — not just the selected target. A paused stream's `poll()` is a no-op. (SPEC §8)
    private func pollFleet() async {
        while !Task.isCancelled {
            for stream in model.streams { await stream.poll() }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
