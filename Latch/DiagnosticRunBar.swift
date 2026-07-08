import SwiftUI
import AppKit
import LatchDomain

/// The on-demand **deep-run launcher** for the inbox: a menu of the diagnostics wired for this
/// target (each gated by capability — no button for a capability that doesn't exist), plus honest
/// run status (failures, clean-run confirmations, recorded `.trace` paths, measured energy). Deep
/// runs with findings flow into the feed as cards; this bar reports the runs that produce no card.
/// (SPEC §1, §8; PLAN slice 12)
struct DiagnosticRunBar: View {
    let model: VitalsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                menu
                if model.isRunningDiagnostic { ProgressView().controlSize(.small) }
                Spacer()
            }
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                Label(note.text, systemImage: note.icon)
                    .font(.caption).foregroundStyle(note.tint)
            }
            if let path = recordedTrace { traceRow(path) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var menu: some View {
        Menu {
            if model.canCheckLeaks {
                Button("Run Leak Check") { Task { await model.checkLeaks() } }
            }
            if model.canRecordTrace {
                Button("Record Leaks Trace") { Task { await model.recordLeakTrace() } }
            }
            if model.canCheckHitches {
                Button("Check for Hangs (sample)") { Task { await model.checkHitches() } }
            }
            if model.canRecordHitchTrace {
                Button("Record Time Profiler Trace") { Task { await model.recordHitchTrace() } }
            }
            if model.canCheckZombies {
                Button("Check for Zombies (relaunch)") { Task { await model.checkZombies() } }
            }
            if model.canMeasureEnergy {
                Button("Measure Energy (powermetrics)") { Task { await model.measureEnergy() } }
            }
        } label: {
            Label("Run deep diagnostic", systemImage: "bolt.badge.clock")
                .font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isRunningDiagnostic)
    }

    /// One honest status line. Failures are orange; clean-run confirmations and measured energy are
    /// muted. A deep run that found something becomes a card, so it is *not* repeated here.
    private struct Note { let text: String; let icon: String; let tint: Color }

    private var notes: [Note] {
        var notes: [Note] = []
        notes += failures
        notes += cleanRuns
        if let measured = model.measuredEnergy {
            notes.append(Note(text: String(format: "Measured energy impact: %.1f", measured),
                              icon: "bolt.fill", tint: LatchTheme.textMuted))
        }
        return notes
    }

    private var failures: [Note] {
        [model.leakMessage, model.traceMessage, model.hitchMessage,
         model.hitchTraceMessage, model.zombieMessage, model.energyMessage]
            .compactMap { $0 }
            .map { Note(text: $0, icon: "exclamationmark.triangle", tint: .orange) }
    }

    private var cleanRuns: [Note] {
        [(model.leakReport, "Leaks"), (model.hitchReport, "Hangs"), (model.zombieReport, "Zombies")]
            .compactMap { report, label -> Note? in
                guard let report, !report.hasFindings else { return nil }
                return Note(text: "\(label): none found", icon: "checkmark.seal", tint: LatchTheme.textMuted)
            }
    }

    /// The most recent recorded trace path (leaks or Time Profiler), if any — a deep run with no
    /// finding card still needs its `.trace` reachable.
    private var recordedTrace: String? {
        model.hitchTraceResult?.tracePath ?? model.traceResult?.tracePath
    }

    private func traceRow(_ path: String) -> some View {
        HStack(spacing: 8) {
            Label(path, systemImage: "doc.badge.gearshape")
                .font(.caption).foregroundStyle(LatchTheme.textFaint)
                .lineLimit(1).truncationMode(.middle)
            Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                .controlSize(.small)
        }
    }
}
