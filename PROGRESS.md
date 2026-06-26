# PROGRESS — Latch

Single source of truth for state. Update the slice row **before** moving on. Append
to the decision log when a non-obvious choice is made. Never delete history.

## Slice status

| # | Slice | Status | Spec ref | Notes |
|---|---|---|---|---|
| 0 | Scaffold & guardrails | ✅ Done | §3, §5 | LatchKit SPM pkg (Domain/Data), CommandRunner + fake, debugger entitlement, Swift 6, CI+lint |
| 1 | Discover & pick local target | ✅ Done | §3.2 | `TargetDiscovery`/`Target` in Domain; `LibprocTargetDiscovery` + `ProcessLister` seam; same-UID filter; searchable picker UI |
| 2 | Live vitals (mem + CPU) | ✅ Done | §3.3, §4 | `MetricsSource`/`VitalsReading`/`MetricSample` in Domain (pure CPU% delta math, % of one core); `LibprocMetricsSource` via `proc_pid_rusage(V6)`+`proc_pidinfo`; `VitalsModel` 1 Hz ring-buffer poller + Swift Charts dashboard |
| 3 | Thresholds & alerting | ⬜ Not started | §3.3, §4 | — |
| 4 | Network I/O | ⬜ Not started | §3.2 | — |
| 5 | Energy / battery | ⬜ Not started | §1, §5 | needs root path |
| 6 | Leaks (attach) | ⬜ Not started | §1 | MallocStackLogging caveat |
| 7 | Zombies (relaunch) | ⬜ Not started | §1 | relaunch-only |
| 8 | Hitches & hangs | ⬜ Not started | §3.3 | — |
| 9 | iOS device support | ⬜ Not started | §1 | dev-signed only |
| 10 | Session report & export | ⬜ Not started | §4 | — |

Legend: ⬜ Not started · 🟦 In progress · ✅ Done · ⚠️ Blocked

## Known constraints / risks (live)
- `task_for_pid` needs debugger entitlement + same-UID; system procs out of scope. (SPEC §1)
- Zombies cannot be enabled on a running process — relaunch required. (SPEC §1, Slice 7)
- `powermetrics` needs root; energy degrades to estimate otherwise. (SPEC §1, Slice 5)
- iOS limited to development-signed apps on connected devices. (SPEC §1, Slice 9)
- Apple APIs/man pages must be verified against current docs, not memory. (SPEC §7)

## Decision log
| Date | Decision | Rationale |
|---|---|---|
| — | Adapter pattern per metric source | Independent testing + swappable backends (SPEC §3.2) |
| — | Two modes per signal: live poll vs deep run | Honest about what cheap APIs can/can't do (SPEC §1) |
| — | Non-sandboxed + notarized | Sandbox incompatible with arbitrary same-UID `task_for_pid` |
| 2026-06-26 | Domain+Data as local SwiftPM pkg `LatchKit`; App links its products | Enforces the dependency rule structurally (Domain target declares no deps) and lets the pure layers run under `swift test` in CI without Xcode (SPEC §3, §6) |
| 2026-06-26 | Modules named `LatchDomain` / `LatchData`, not `Domain` / `Data` | Avoids shadowing `Foundation.Data` at call sites that import both; layer names stay Domain/Data conceptually |
| 2026-06-26 | App: Swift 6 mode, sandbox OFF, hardened runtime ON, only `com.apple.security.cs.debugger` | Minimal entitlements per code-signing skill; sandbox removed `files.user-selected.read-only` stray (SPEC §1, §5) |
| 2026-06-26 | `ProcessCommandRunner` runs blocking process work off the cooperative pool | Keeps `async` callers unblocked; large-concurrent-output pipe-drain hardening deferred until a real adapter needs it |
| 2026-06-26 | libproc enumeration sits behind a `ProcessLister` seam (not `CommandRunner`) | libproc is a C API, not a shell call; the seam lets the same-UID filter + name mapping be tested with canned `ProcessEntry` fixtures without touching the kernel (SPEC §6) |
| 2026-06-26 | `TargetDiscovery` protocol exposes only `localProcesses()` for now | YAGNI: `devices()`/`apps(on:)` from SPEC §3.1 need a `Device` type owned by slice 9; no production code without a failing test that requires it |
| 2026-06-26 | Per-pid UID read via `proc_pidinfo(PROC_PIDTBSDINFO).pbi_uid`; path via `proc_pidpath` | Verified against on-machine SDK headers; `PROC_PIDPATHINFO_MAXSIZE` is not exposed to Swift so the buffer is sized as `4 * MAXPATHLEN` to match `<sys/proc_info.h>` (SPEC §7) |
| 2026-06-26 | Split raw `VitalsReading` (Domain value, cumulative counters) from derived `MetricSample` (cpuPercent + mem + threads) | CPU has no instantaneous reading; the pure `MetricSample.derive(from:to:)` delta math lives in Domain and is TDD'd deterministically, while the live read stays in the adapter (SPEC §6) |
| 2026-06-26 | CPU% expressed as **% of one core** (cpuΔ/wallΔ×100, can exceed 100) | Matches the SPEC §3.3 threshold ("> 80% of one core"); both `ri_user/system_time` and `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` are nanoseconds so the ratio needs no mach-timebase conversion (verified vs `<sys/resource.h>`, SPEC §7) |
| 2026-06-26 | `LibprocMetricsSource` uses `proc_pid_rusage(RUSAGE_INFO_V6)` for CPU+footprint+resident and `proc_pidinfo(PROC_PIDTASKINFO).pti_threadnum` for threads | `ri_phys_footprint` matches the Xcode gauge without needing `task_for_pid`; struct flavor/fields verified against on-machine headers; `derive` guards zero-interval and counter-rewind (pid reuse) (SPEC §7) |
| 2026-06-26 | 1 Hz poll loop lives in the view's `.task`, not the model | SwiftUI cancels `.task` on disappear; keeps `VitalsModel` to the tested `poll()` (ring buffer + delta) with no untested timer/Task machinery as production code |

## Changelog
- 2026-06-26 — **Slice 2 (Live vitals: memory + CPU) landed.** Domain gained the raw
  `VitalsReading` (cumulative CPU time, phys footprint, resident, threads, monotonic
  wall-clock), the derived `MetricSample` (cpuPercent as % of one core, footprint MiB,
  threads) with the pure `MetricSample.derive(from:to:)` delta math, and the
  `MetricsSource` port. Data gained `LibprocMetricsSource` —
  `proc_pid_rusage(RUSAGE_INFO_V6)` for CPU time (`ri_user_time`+`ri_system_time`) +
  `ri_phys_footprint`/`ri_resident_size`, `proc_pidinfo(PROC_PIDTASKINFO).pti_threadnum`
  for threads, `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` for the stamp (all verified
  against on-machine SDK headers). Presentation: `@MainActor @Observable VitalsModel`
  (1 Hz `poll()`, baseline-then-delta, bounded ring buffer) and a `VitalsView` Swift
  Charts dashboard (CPU% + footprint line charts, live PID/CPU/mem/threads header),
  wired into the picker's detail. TDD red-first: Domain `MetricSampleTests` (delta math
  exact at 50%/200%, zero-interval and counter-rewind guards, footprint MiB
  conversion); Data `LibprocMetricsSourceTests` (real read of own pid is plausible,
  bogus pid throws); Presentation `VitalsModelTests` (baseline tick, delta tick, ring
  cap, error path) via `FakeMetricsSource`. `swift test` green (13/13), `xcodebuild
  test` green (app + UI), BUILD SUCCEEDED with zero warnings.
- 2026-06-26 — **Slice 1 (Discover & pick a local target) landed.** Domain gained
  `Target` (id/kind/pid/bundleID/displayName/deviceUDID) and the `TargetDiscovery`
  protocol (`localProcesses()`). Data gained the `ProcessLister` seam (`ProcessEntry`
  + protocol), the libproc-backed `LibprocProcessLister`
  (`proc_listpids`/`proc_pidpath`/`proc_pidinfo(PROC_PIDTBSDINFO)`, verified against SDK
  headers), and `LibprocTargetDiscovery` which filters to the current UID (SPEC §1) and
  maps entries to `[Target]`. TDD: `LibprocTargetDiscoveryTests` (maps entries, filters
  other-UID pids, skips pathless entries) and `TargetPickerModelTests` (load, search
  filter, select) written red-first via `FakeProcessLister`/`FakeTargetDiscovery`.
  Presentation: `@MainActor @Observable TargetPickerModel` + a searchable
  `NavigationSplitView` process picker wired to the real libproc discovery. `swift test`
  green (6/6), `xcodebuild test` green (app + UI), BUILD SUCCEEDED with zero warnings.
- 2026-06-26 — **Slice 0 (Scaffold & guardrails) landed.** Local SwiftPM package
  `LatchKit` with `LatchDomain` (`SignalKind`) and `LatchData` (`CommandRunner`,
  `CommandResult`, `ProcessCommandRunner`) layers; App target links both products.
  TDD: `SignalKindTests` (Domain builds with zero outward imports) and
  `CommandRunnerTests` (fake returns canned stdout; real runner captures `/bin/echo`)
  written red-first, now green. App on Swift 6 strict concurrency, App Sandbox OFF,
  Hardened Runtime ON, `com.apple.security.cs.debugger` entitlement (verified in the
  signed binary). SwiftLint config + GitHub Actions CI (package tests · app build ·
  lint). `swift test` green (3/3), `xcodebuild` BUILD SUCCEEDED with zero warnings.
