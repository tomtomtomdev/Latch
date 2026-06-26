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

## Slice 11 — Main window shell + live timeline (design handoff)
- Recreate the main-window chrome from `SPEC.md §8` / the handoff in SwiftUI/AppKit:
  toolbar (target title + latched status, live metric chips, `30s/1m/5m` range, pause/resume,
  settings), sidebar (attached targets with health dot + issue badge + `Attach process…`),
  center **live timeline** with the honest live lanes (CPU, Memory, Network, Energy *estimate*),
  right-panel placeholder. Match the binding tokens (lane colors, teal accent, dark surfaces).
- **Honesty (SPEC §1/§8):** live lanes only; the Frame-time lane is gated/labelled as a hint
  until slice 8; **no** live zombie lane; energy lane is the watts estimate, labelled as such.
  Pause/Resume gates the poll loop; range maps to the per-target ring buffer window (≤ cap).
- **Test:** chip/lane values bind to the latest `MetricSample`; pause stops appends; changing
  range trims the visible window; selecting a sidebar target swaps the streamed target.
  (View-model tests; pixel-exact layout via optional snapshot, not load-bearing.)

## Slice 12 — Detection inbox + diagnostic detail
- Right-panel inbox merging **live threshold `Alert`s** (§3.3) and **deep-run findings**
  (slices 6–8) into one provenance-tagged feed (newest first, capped). Each card states its
  provenance (live hint vs measured/deep + which adapter). Card → diagnostic detail (meta grid,
  call tree + stack trace from the deep run, suggested fix, `Symbolicate` / `Copy trace`).
- Timeline **detection markers** + click-to-select wired to the same feed; back returns to inbox.
- **Honesty (SPEC §8):** symbolication is the on-demand action; live hints never masquerade as
  symbolicated deep findings.
- **Test:** feed orders + caps; selecting a marker or card opens its detail; provenance shown;
  empty ("0 detections") state.

## Slice 13 — Menu-bar companion (mini mode)
- The status-item dropdown from `SPEC.md §8` via `NSStatusItem` + popover: per-target health
  line (CPU/MEM/NET summary + status), recent detections (≤3), `Pause all` / `Resume all` /
  `Open Latch`. Glanceable health across all attached targets.
- **Test:** dropdown lists attached targets with health/issue counts; `Pause all` toggles every
  poller; the recent-detections list reflects the slice-12 feed.

---

## Backlog / later
- MetricKit companion for iOS targets you own (post-hoc real energy/hang reports).
- Multi-target side-by-side comparison.
- Baseline capture + regression gate (CI hook).
