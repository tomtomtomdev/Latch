import SwiftUI
import AppKit
import LatchDomain

/// The on-demand **deep run** diagnostics for a latched target — distinct from the live
/// polling lanes in `VitalsView`. Groups the two deep-run sections: Leaks (attach, no
/// relaunch) and Zombies (relaunch-only). Each states its provenance and honest constraints
/// (MallocStackLogging for leak backtraces; relaunch for zombies). (SPEC §1, §8; PLAN slices 6–7)
struct DeepDiagnosticsView: View {
    let model: VitalsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            leaksSection
            zombiesSection
        }
    }

    /// Leaks: an on-demand deep run, distinct from the live signals. "Run Leak Check"
    /// attaches with `leaks` for a quick findings list; "Record Trace" captures an `xctrace`
    /// Leaks trace to open in Instruments. Backtraces (the *where*) need launch-time
    /// MallocStackLogging — surfaced honestly when they are absent. (SPEC §1; PLAN slice 6)
    @ViewBuilder private var leaksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leaks").font(.headline)
            HStack(spacing: 12) {
                if model.canCheckLeaks {
                    Button("Run Leak Check", systemImage: "magnifyingglass") {
                        Task { await model.checkLeaks() }
                    }
                }
                if model.canRecordTrace {
                    Button("Record Trace", systemImage: "record.circle") {
                        Task { await model.recordLeakTrace() }
                    }
                }
                if model.isRunningDiagnostic { ProgressView().controlSize(.small) }
            }
            .disabled(model.isRunningDiagnostic)
            Text("Leak check attaches with leaks (no relaunch). Backtraces need the target "
                + "launched with MallocStackLogging; a deep trace opens in Instruments.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let report = model.leakReport { leakReport(report) }
            if let message = model.leakMessage { caveat(message, icon: "exclamationmark.triangle") }
            if let path = model.traceResult?.tracePath { traceRow(path) }
            if let message = model.traceMessage { caveat(message, icon: "lock.fill") }
        }
    }

    @ViewBuilder private func leakReport(_ report: DiagnosticResult) -> some View {
        reportSummary(report)
        if report.hasFindings && !report.hasBacktraces {
            caveat(
                "No backtraces — relaunch the target with MallocStackLogging=1 to see where "
                    + "leaks were allocated.",
                icon: "info.circle"
            )
        }
        ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
            leakFinding(finding)
        }
    }

    private func leakFinding(_ finding: Finding) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(finding.title).font(.callout).textSelection(.enabled)
            Text("\(finding.instanceCount)× · \(finding.byteCount) bytes")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(finding.backtrace.enumerated()), id: \.offset) { _, frame in
                Text(frame).font(.caption2).monospaced().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func traceRow(_ path: String) -> some View {
        HStack(spacing: 8) {
            Label(path, systemImage: "doc.badge.gearshape")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Open in Instruments", systemImage: "arrow.up.forward.app") {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
            .controlSize(.small)
        }
    }

    /// Zombies: a deep, **relaunch-only** run. Latch cannot detect zombies on the running
    /// process — `NSZombieEnabled` is read at launch — so "Check for Zombies" starts a fresh
    /// instance of the target under that env var and reports any over-release messages. The UI
    /// states this plainly; without an executable path to relaunch, the action is unavailable.
    /// (SPEC §1, §8; PLAN slice 7)
    @ViewBuilder private var zombiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zombies").font(.headline)
            HStack(spacing: 12) {
                if model.canCheckZombies {
                    Button("Check for Zombies (relaunch)", systemImage: "ant") {
                        Task { await model.checkZombies() }
                    }
                }
                if model.isRunningDiagnostic { ProgressView().controlSize(.small) }
            }
            .disabled(model.isRunningDiagnostic)
            Text("Zombie detection can't attach to a running process — NSZombieEnabled is read "
                + "at launch. This relaunches the target as a fresh instance; the live process "
                + "above is unaffected. Findings name the method sent to a deallocated object.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.canCheckZombies {
                caveat("Relaunch unavailable — no executable path for this target.", icon: "info.circle")
            }
            if let report = model.zombieReport { zombieReport(report) }
            if let message = model.zombieMessage { caveat(message, icon: "exclamationmark.triangle") }
        }
    }

    @ViewBuilder private func zombieReport(_ report: DiagnosticResult) -> some View {
        reportSummary(report)
        ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).font(.callout).monospaced().textSelection(.enabled)
                Text("messaged \(finding.instanceCount)× after deallocation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    /// The one-line outcome of a deep diagnostic run — red when it found something, green when
    /// it came back clean. Shared by the leak and zombie reports.
    private func reportSummary(_ report: DiagnosticResult) -> some View {
        Text(report.summary)
            .font(.callout.weight(.medium))
            .foregroundStyle(report.hasFindings ? .red : .green)
    }

    private func caveat(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
