# SPEC — Latch

> Working name: **Latch** (it "latches onto" a running process). Rename freely.

A native macOS app that attaches to a running process — a local macOS app, or an
iOS app on a connected, development-signed device — and surfaces six health signals:
**memory leaks, zombies (over-released objects), performance hitches/hangs, CPU
spikes, high network I/O, and high battery/energy usage.**

This spec is the source of truth. `PLAN.md` slices implement it; `PROGRESS.md`
tracks it; `CLAUDE.md` governs how the agent works on it.

---

## 1. The honest constraints (read this first)

Latch is **not magic**. It is a friendly GUI orchestrator over the same sanctioned
Apple mechanisms that Instruments, Activity Monitor, `leaks`, and `powermetrics`
already use. Building a profiler means living inside these hard limits. Do not let
any slice pretend otherwise.

| Capability | Reality | Consequence for Latch |
|---|---|---|
| Read another process's task port (`task_for_pid`) | Requires the `com.apple.security.cs.debugger` entitlement, hardened-runtime signing, and works only for **your own UID's** processes. SIP-protected / system / other-user processes are off-limits without disabling SIP or running as root. | Latch targets the **user's own** apps. System processes are out of scope. |
| Cheap per-process metrics (`proc_pid_rusage`, `proc_pidinfo`) | Works for same-UID processes without a task port. This is the low-friction path. | This is the backbone of the live dashboard (memory footprint, CPU, disk I/O, energy estimate). |
| **Zombie** detection (`NSZombieEnabled`) | Must be injected as an **environment variable at launch**. You cannot retroactively enable it on an already-running process. | The Zombies feature must **relaunch** the target under instrumentation. "Latch onto running" does not apply to zombies — be explicit in the UI. |
| **Leak** detection | `leaks <pid>` / xctrace `Leaks` template can attach to a running same-UID process. Accuracy improves if `MallocStackLogging` was set at launch. | Leaks can attach live, but malloc stack backtraces (the part that tells you *where* the leak came from) need launch-time `MallocStackLogging`. |
| **Energy / battery** (`powermetrics`) | Requires **root** (sudo). Per-process energy via `--samplers tasks`. | Energy sampling prompts for privilege escalation, or degrades to the cheaper `ri_energy_nj` power estimate from rusage. |
| **iOS** profiling | Only **development-signed** apps on a **connected, unlocked, paired** device. App Store apps cannot be profiled. Tooling: `xctrace` and `xcrun devicectl`. | iOS support is gated on a dev-provisioned target + device. App Store / arbitrary apps are out of scope. |
| **Battery from inside an iOS app** | `MetricKit` (`MXMetricManager`) reports real energy/hang/CPU/memory daily, but requires SDK integration in the *target* and is *post-hoc*. | Offered as an optional complement for iOS targets you own — not part of external attach. |

**Design principle that falls out of this:** Latch has two operating modes per
signal — **(a) live polling** of cheap kernel APIs for at-a-glance dashboards and
threshold alerting, and **(b) on-demand deep runs** via `xctrace`/CLI tools for
root-causing. Never conflate the two in the UI.

---

## 2. Goals / Non-goals

**Goals**
- Attach to a running same-UID macOS process and show live memory footprint, CPU%,
  thread count, disk I/O, network I/O, and an energy estimate.
- Threshold-based alerting for the six signals with sane, user-tunable defaults.
- On-demand deep diagnostics: Leaks, Zombies, Time Profiler (hitch/hang), Allocations,
  Network, Energy — each backed by a named `xctrace` template.
- Support iOS targets that are development-signed on a connected device.
- Export a session report (metrics timeline + any captured `.trace` paths).

**Non-goals (v1)**
- Profiling system processes, other users' processes, or App Store iOS apps.
- Replacing Instruments' deep analysis UI — Latch *launches and summarizes* runs,
  it does not re-implement the trace viewer.
- Jailbreak, SIP-disabled, or any unsanctioned attach path.
- Cross-platform (Linux/Windows targets).

---

## 3. Architecture

Clean Architecture, three layers, dependency rule points inward. SwiftUI + Swift 6
strict concurrency. Source-agnostic **adapter pattern** so each backend (libproc,
xctrace, powermetrics, nettop, devicectl) is swappable and individually testable —
the same pattern as a source-agnostic data layer, applied to metric sources.

```
Presentation (SwiftUI)         Views, @Observable view models, charts, alert banners
        │  depends on
Domain (pure Swift, no I/O)    Entities: Target, MetricSample, Signal, Threshold, Alert,
        │  depends on          DiagnosticRun. UseCases: AttachToTarget, PollMetrics,
        ▼  abstractions only   EvaluateThresholds, RunDiagnostic, ExportReport.
Data (adapters + system I/O)   MetricsSource / DiagnosticRunner / TargetDiscovery
                               protocol implementations.
```

### 3.1 Core protocols (Domain owns the abstractions)

```swift
protocol TargetDiscovery {                       // enumerate attachable targets
    func localProcesses() async throws -> [Target]
    func devices() async throws -> [Device]
    func apps(on device: Device) async throws -> [Target]
}

protocol MetricsSource {                          // live polling backend
    var supportedSignals: Set<SignalKind> { get }
    func sample(_ target: Target) async throws -> MetricSample
}

protocol DiagnosticRunner {                       // deep, on-demand runs
    var kind: DiagnosticKind { get }              // .leaks .zombies .hitches .allocations .network .energy
    var requiresRelaunch: Bool { get }            // true for .zombies
    func run(_ target: Target, options: DiagnosticOptions) async throws -> DiagnosticResult
}
```

### 3.2 Concrete adapters (Data layer)

| Adapter | Backs | Mechanism |
|---|---|---|
| `LibprocMetricsSource` | CPU, memory, disk I/O, energy estimate, thread/zombie-process count | `proc_pid_rusage(RUSAGE_INFO_V6)`, `proc_pidinfo(PROC_PIDTASKINFO)` |
| `NettopMetricsSource` | network I/O | shell `nettop -P -L 1 -J bytes_in,bytes_out -p <pid>` |
| `PowermetricsSource` | energy/battery (high fidelity) | privileged `powermetrics --samplers tasks` (needs root) |
| `XctraceDiagnosticRunner` | leaks, zombies, hitches, allocations, network, energy | `xctrace record --template … --attach <pid>` or `--launch`/`--device` + `xctrace export` to parse |
| `LeaksCLIRunner` | quick leak snapshot | shell `leaks <pid>` |
| `SampleSpindumpRunner` | hang/hitch quick look | `sample <pid>`, `spindump <pid>` |
| `DevicectlTargetDiscovery` | iOS device + app enumeration | `xcrun devicectl list devices` / `list processes` |
| `LibprocTargetDiscovery` | local process list | `proc_listpids`, `proc_pidpath` |

Each adapter is replaceable by a `Fake…` double in tests. No adapter leaks `Process`,
`mach_*`, or C interop types past the Data boundary — they map to Domain entities.

### 3.3 The six signals → backing

| Signal | Live indicator | Deep diagnostic | Default threshold (tunable) |
|---|---|---|---|
| Memory leak | `ri_phys_footprint` trend (monotonic rise over N samples) | xctrace `Leaks` (attach) | sustained rise > 2 MB/min over 5 min |
| Zombies | n/a (can't detect live) | xctrace `Zombies` (**relaunch only**) | any zombie message detected |
| Hitch / hang | main-thread CPU stall heuristic from sampling | `Time Profiler` / `spindump` / `sample` | main thread blocked > 250 ms (hang); frame > 16.7 ms |
| CPU spike | CPU% from `ri_user_time`+`ri_system_time` delta | `Time Profiler` | > 80% of one core for > 3 s |
| Network I/O | `nettop` bytes_in/out rate | xctrace `Network` | > 5 MB/s sustained 5 s |
| Battery/energy | `ri_energy_nj` power estimate (W); `powermetrics` measured impact if root | xctrace `Energy Log` | est. power > 5 W sustained 5 s (measured impact is a display upgrade) |

> Thresholds are **defaults**, not science. They ship configurable and are stored
> per-target. Document them in-app as starting points.

---

## 4. Data model (Domain entities)

- `Target { id, kind: .localMac | .iOSDevice, pid?, bundleID?, displayName, deviceUDID? }`
- `MetricSample { timestamp, cpuPercent, physFootprintBytes, residentBytes, threadCount, diskReadBytes, diskWriteBytes, netInBytesPerSec, netOutBytesPerSec, energyEstimate }`
- `SignalKind { memoryLeak, zombies, hitch, cpuSpike, networkIO, battery }`
- `Threshold { signal, comparator, value, window }`
- `Alert { signal, severity, firedAt, sample }`
- `DiagnosticRun { kind, startedAt, finishedAt, tracePath?, summary, findings: [Finding] }`

Live samples are a ring buffer per target (cap memory; e.g. 1 h at 1 Hz). Samples
and diagnostic runs persist via SwiftData (offline, provenance-aware: every value
records which adapter produced it).

---

## 5. Permissions & trust

- Non-sandboxed, hardened-runtime, **notarized** developer tool (matches the
  debugger-entitlement requirement; the sandbox is incompatible with `task_for_pid`
  on arbitrary same-UID pids).
- Entitlement: `com.apple.security.cs.debugger`.
- Privileged energy sampling uses a clearly-labelled, user-initiated escalation
  (the app asks; it never silently runs `sudo`). If the user declines, energy
  degrades to the rusage estimate.
- Latch only ever attaches to targets the user explicitly selects.

## 6. Testing strategy

- **Domain**: pure unit tests, no I/O. Threshold evaluation, leak-trend heuristic,
  rate computation from byte deltas — all deterministic, all TDD'd first.
- **Data adapters**: parsing tests against **recorded fixture output** (captured
  real `nettop` / `xctrace export` / `leaks` text checked into `Fixtures/`). The
  shell call is behind a `CommandRunner` protocol so tests inject canned stdout.
- **Presentation**: view-model tests with `Fake` sources; snapshot tests optional.
- **Integration smoke**: one manual checklist (real attach to a throwaway app) per
  release — documented, not in CI, because it needs entitlements + a real device.

## 7. Out-of-band references

Apple APIs change and memory is unreliable for them. Before implementing any
adapter, the relevant skill (`apple-process-metrics`, `instruments-xctrace`,
`code-signing-entitlements`, `macos-apple-docs`, `ios-apple-docs`) **must be
consulted and its claims verified against current official docs / man pages /
`xctrace list templates`** — not against the agent's training data.

---

## 8. User interface (design handoff)

The authoritative UI/visual spec is the **design handoff** in
`design_handoff_latch_profiler/` — `README.md` (written spec: layout, design tokens,
interactions) and `Latch.dc.html` (an interactive HTML prototype). It is **high-fidelity**:
colors, typography, spacing, layout, and interactions are to be reproduced precisely in
SwiftUI/AppKit. The HTML's inlined runtime / base64 machinery is **not** production code —
treat the bundle purely as a visual + interaction reference.

**Two surfaces:** a **main window** (live deep-dive on one attached target — toolbar with
live metric chips + range/pause controls, a sidebar of attached targets, a center live
timeline of lanes, and a right-hand detection inbox / diagnostic detail) and a **menu-bar
companion dropdown** (glanceable health across all attached targets). Native macOS dark
pro-tool aesthetic (Instruments / Activity Monitor / Xcode).

**The prototype fakes all data.** In production every value comes from the §3.2 adapters.
Where the handoff's continuous "detection stream" conflicts with the honest constraints of
§1, **§1 wins** and the UI must keep *live polling* and *on-demand deep runs* visually
distinct (§1's core design principle — never conflate them). This reconciliation is binding:

| Handoff element | Honest mapping (binding) |
|---|---|
| 5 live lanes: CPU, Memory, Network, Energy, Frame time | CPU/Memory (slice 2) and Network (slice 4) are genuine live lanes. **Energy** live lane = the `ri_energy_nj` **watts estimate** (slice 5); measured `powermetrics` impact is an on-demand upgrade, not a live lane. **Frame time** is not a cheap live counter for an external attach — it is a sampling **hint** + deep run (§3.3, slice 8); render it as a hint lane or gate it, never as ground-truth frame timing. |
| "Zombie object messaged" as a live detection | **Impossible live.** Zombies require relaunch under `NSZombieEnabled` (§1, slice 7). The timeline must not stream live zombie detections; zombies appear only as a deep, relaunch-gated run. |
| Detection cards with symbolicated **call tree** + **stack trace** + "Symbolicate" | Deep-run output (`xctrace`/`leaks`/`sample`/`spindump`, slices 6–8) + export (slice 10) — **on-demand**, not part of the live stream. The inbox blends live threshold alerts (§3.3) with deep-run findings; every card shows its **provenance** (which adapter / live vs deep). |
| iOS + watchOS targets streaming live vitals | iOS = **development-signed only**, on a connected/paired/unlocked device, via `xctrace`/`devicectl` (§1, slice 9) — not cheap 20 Hz `libproc` streaming. **watchOS is out of scope** (§2). Sample sidebar rows are illustrative; real rows obey §1 eligibility and say why an ineligible target can't attach. |
| "streaming · 20 Hz" | Live **sampling** stays on cheap APIs at the slice-2 cadence (~1 Hz); a faster canvas redraw is a presentation choice only, and sampling pauses when the app is not frontmost (per the handoff's own implementation note). |
| Range control `30s · 1m · 5m` | Maps to the per-target ring buffer (§4); windows must be ≤ the retention cap. |

**Design tokens** (full palette, type scale, radii, shadows) live in the handoff README and
are the single source — not duplicated here. Binding accents: lane colors CPU `#FF9F0A` ·
Memory `#BF5AF2` · Network `#64D2FF` · Energy `#30D158` · Frame `#FF375F`; Latch teal
`#2DD4BF`; severity Critical `#FF453A` / Warning `#FF9F0A` / Info `#0A84FF`.

The redesign is scheduled as PLAN slices 11–13 (it depends on the data slices it
visualizes); the current functional dashboard is the interim UI until then.
