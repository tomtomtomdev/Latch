# PLAN — Latch

Vertical, demoable slices. Each slice ships a thin end-to-end path (Domain → Data →
UI) and is built **spec-first, then test, then code, then refactor** (see `CLAUDE.md`).
Run one slice at a time via the slice loop. Do not start a slice until the previous
one is green and its row in `PROGRESS.md` is updated.

A slice is **Done** when: spec ref noted · failing test written first · implementation
green · refactored · no new compiler/concurrency warnings · `PROGRESS.md` updated ·
constraints from `SPEC.md §1` respected (no fake capabilities).

---

## Slice 0 — Scaffold & guardrails
- Xcode project, Swift 6 strict concurrency, three SPM/local-package targets:
  `Domain`, `Data`, `App` (Presentation). Dependency rule enforced (Domain imports nothing).
- Hardened runtime + `com.apple.security.cs.debugger` entitlement wired; signing config.
- `CommandRunner` protocol + real `ProcessCommandRunner` + `FakeCommandRunner`.
- CI: build + unit tests (Anvil / xcc). Lint (Detekt-equivalent: SwiftLint/SwiftFormat).
- **Test:** Domain target compiles with zero outward imports; `FakeCommandRunner`
  returns canned stdout.

## Slice 1 — Discover & pick a local target
- `LibprocTargetDiscovery.localProcesses()` → same-UID processes with name + pid + path.
- UI: searchable process list; select one to "latch".
- **Test:** discovery maps `proc_listpids`/`proc_pidpath` fixtures to `[Target]`;
  filters out non-same-UID pids.

## Slice 2 — Live vitals dashboard (memory + CPU)
- `LibprocMetricsSource.sample()` via `proc_pid_rusage(V6)` + `proc_pidinfo`.
- CPU% from user+system time deltas between samples; footprint from `ri_phys_footprint`.
- UI: 1 Hz line charts for footprint and CPU%, thread count, ring-buffer retention.
- **Test:** CPU% delta math is exact for synthetic samples; footprint conversion correct.

## Slice 3 — Thresholds & alerting
- `EvaluateThresholds` use case; default `Threshold`s from `SPEC.md §3.3`; per-target overrides.
- Memory-leak heuristic: monotonic-rise detector over a window (the live leak *hint*).
- UI: alert banners + per-signal status pills; settings to tune thresholds.
- **Test:** rise detector fires on rising series, ignores noisy-flat; comparator logic.

## Slice 4 — Network I/O
- `NettopMetricsSource` parsing `nettop -P -L 1 -J bytes_in,bytes_out -p <pid>`.
- Rate computation from byte deltas; merge into dashboard + threshold.
- **Test:** parse recorded `nettop` fixture → bytes; rate from deltas; handles 0/!found.

## Slice 5 — Energy / battery
- `PowermetricsSource` (privileged) with explicit, user-initiated escalation prompt.
- Graceful degrade to `ri_billed_energy` estimate when privilege declined.
- UI: energy tier + estimate; clear "estimate vs measured" labelling.
- **Test:** parse `powermetrics --samplers tasks` fixture; degrade path selects estimate.

## Slice 6 — Leaks (deep, on-demand, attach)
- `XctraceDiagnosticRunner(.leaks)` → `xctrace record --template Leaks --attach <pid>`
  then `xctrace export` parse; plus quick `LeaksCLIRunner` (`leaks <pid>`).
- UI: "Run Leak Check" → progress → findings list + `.trace` path to open in Instruments.
- Surface the `MallocStackLogging` caveat in UI when backtraces are absent.
- **Test:** parse `leaks` + `xctrace export` fixtures → `[Finding]`; handle "0 leaks".

## Slice 7 — Zombies (deep, **relaunch only**)
- `XctraceDiagnosticRunner(.zombies)`, `requiresRelaunch = true`; launches target
  under the Zombies template with `NSZombieEnabled` handled by xctrace.
- UI must state plainly: zombies require relaunching the app (cannot attach live).
- **Test:** runner reports `requiresRelaunch`; UI gates the action; fixture parse.

## Slice 8 — Hitches & hangs
- `Time Profiler` via xctrace + quick `sample`/`spindump` runners.
- Main-thread stall heuristic from samples → live hitch hint; deep run for stacks.
- **Test:** hang heuristic flags > 250 ms main-thread block in synthetic stack series.

## Slice 9 — iOS device support
- `DevicectlTargetDiscovery`: `xcrun devicectl list devices` / list processes.
- Gate to development-signed apps on connected, paired, unlocked devices; clear
  messaging when a target is ineligible (App Store / no dev provisioning).
- Route diagnostics through `xctrace --device <udid>`.
- **Test:** parse `devicectl` JSON fixtures; ineligible-target messaging logic.

## Slice 10 — Session report & export
- `ExportReport`: metrics timeline + alert log + diagnostic-run summaries + `.trace`
  paths → a single shareable bundle (JSON + optional Markdown summary).
- **Test:** report serialization round-trips; includes provenance per metric.

---

## Backlog / later
- MetricKit companion for iOS targets you own (post-hoc real energy/hang reports).
- Menu-bar mini mode (ties to existing status-bar app patterns).
- Multi-target side-by-side comparison.
- Baseline capture + regression gate (CI hook).
