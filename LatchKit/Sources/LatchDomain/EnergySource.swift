// LatchDomain — pure Swift, imports nothing outward. (SPEC §3)

/// Reads a higher-fidelity, *measured* per-process energy figure on demand. Domain owns
/// the abstraction; the Data layer supplies a `powermetrics`-backed implementation that
/// needs root. This is the on-demand deep read (SPEC §1's "deep run" mode) — distinct from
/// the always-available `ri_energy_nj` estimate that rides every live tick. When the tool
/// is unavailable or unprivileged the call throws and the caller degrades to the estimate.
/// (SPEC §3.2, §3.3; PLAN slice 5)
public protocol EnergySource: Sendable {
    /// The measured per-process "energy impact" for `pid` — `powermetrics`' rough, unitless
    /// proxy for total energy (CPU + GPU + disk + network). Throws `EnergyMeasurementError`
    /// when the privileged tool cannot run.
    func measuredEnergyImpact(pid: Int32) async throws -> Double
}

/// Why a measured-energy read failed. `powermetrics` needs root; without it the read is
/// unavailable and the UI falls back to the estimate — this is an expected limitation, not
/// a crash. (SPEC §1, §5)
public enum EnergyMeasurementError: Error, Equatable {
    /// The tool exited non-zero (commonly "must be run as the superuser") or produced no
    /// parseable sample.
    case unavailable
    /// The sample parsed, but carried no row for the requested pid (process not running
    /// during the sample window).
    case processNotFound(pid: Int32)
}
