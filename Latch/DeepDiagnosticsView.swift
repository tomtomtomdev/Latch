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
            hitchesSection
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
            findingRow(
                title: finding.title,
                subtitle: "\(finding.instanceCount)× · \(finding.byteCount) bytes",
                monospacedTitle: false,
                backtrace: finding.backtrace
            )
        }
    }

    /// One finding row shared by every deep-run report: a selectable title, a one-line
    /// subtitle, and any backtrace frames. `monospacedTitle` is on for symbol/selector titles
    /// (hitches, zombies) and off for leak signatures.
    private func findingRow(
        title: String, subtitle: String, monospacedTitle: Bool, backtrace: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout).monospaced(monospacedTitle).textSelection(.enabled)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(backtrace.enumerated()), id: \.offset) { _, frame in
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

    /// Hitches & hangs: a deep run, distinct from the live signals. "Check for Hangs" samples
    /// the running process (`sample <pid>`, no relaunch) and flags a main-thread stack wedged
    /// past the hang bar; "Record Time Profiler Trace" captures an `xctrace` trace to open in
    /// Instruments. The stall verdict is an honest sampling *hint* — a main thread parked in
    /// its run loop reads the same — so the trace is the ground truth. (SPEC §1, §3.3; PLAN slice 8)
    @ViewBuilder private var hitchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hitches & Hangs").font(.headline)
            HStack(spacing: 12) {
                if model.canCheckHitches {
                    Button("Check for Hangs (sample)", systemImage: "gauge.with.needle") {
                        Task { await model.checkHitches() }
                    }
                }
                if model.canRecordHitchTrace {
                    Button("Record Time Profiler Trace", systemImage: "record.circle") {
                        Task { await model.recordHitchTrace() }
                    }
                }
                if model.isRunningDiagnostic { ProgressView().controlSize(.small) }
            }
            .disabled(model.isRunningDiagnostic)
            Text("Sampling attaches with sample (no relaunch) and flags a main-thread stack "
                + "wedged > 250 ms. It's an honest hint — a main thread idling in its run loop "
                + "looks similar; the Time Profiler trace is the ground truth.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let report = model.hitchReport { hitchReport(report) }
            if let message = model.hitchMessage { caveat(message, icon: "exclamationmark.triangle") }
            if let path = model.hitchTraceResult?.tracePath { traceRow(path) }
            if let message = model.hitchTraceMessage { caveat(message, icon: "lock.fill") }
        }
    }

    @ViewBuilder private func hitchReport(_ report: DiagnosticResult) -> some View {
        reportSummary(report)
        ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
            findingRow(
                title: finding.title,
                subtitle: "main thread wedged across \(finding.instanceCount) samples",
                monospacedTitle: true,
                backtrace: finding.backtrace
            )
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
            findingRow(
                title: finding.title,
                subtitle: "messaged \(finding.instanceCount)× after deallocation",
                monospacedTitle: true,
                backtrace: finding.backtrace
            )
        }
    }

    /// The one-line outcome of a deep diagnostic run — red when it found something, green when
    /// it came back clean. Shared by the leak, hitch, and zombie reports.
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
