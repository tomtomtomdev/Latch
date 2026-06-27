# PROGRESS — Latch

Single source of truth for state. Update the slice row **before** moving on. Append
to the decision log when a non-obvious choice is made. Never delete history.

## Slice status

| # | Slice | Status | Spec ref | Notes |
|---|---|---|---|---|
| 0 | Scaffold & guardrails | ✅ Done | §3, §5 | LatchKit SPM pkg (Domain/Data), CommandRunner + fake, debugger entitlement, Swift 6, CI+lint |
| 1 | Discover & pick local target | ✅ Done | §3.2 | `TargetDiscovery`/`Target` in Domain; `LibprocTargetDiscovery` + `ProcessLister` seam; same-UID filter; searchable picker UI |
| 2 | Live vitals (mem + CPU) | ✅ Done | §3.3, §4 | `MetricsSource`/`VitalsReading`/`MetricSample` in Domain (pure CPU% delta math, % of one core); `LibprocMetricsSource` via `proc_pid_rusage(V6)`+`proc_pidinfo`; `VitalsModel` 1 Hz ring-buffer poller + Swift Charts dashboard |
| 3 | Thresholds & alerting | ✅ Done | §3.3, §4 | Domain `Comparator`/`Threshold`(+`defaults`)/`Alert`/`AlertSeverity` + pure `EvaluateThresholds` (sustained CPU breach + least-squares footprint-rise leak hint); `VitalsModel` recomputes active alerts per tick + per-target `updateThreshold`; UI signal pills (honest `unavailable` for non-live signals), alert banners, threshold-tuning popover |
| 4 | Network I/O | ✅ Done | §3.2, §3.3 | Domain `NetworkReading`(raw cumulative bytes)+`NetworkRate`(pure `derive` rate math, guards zero-interval/rewind)+`NetworkSource` port; `MetricSample` grew net rate fields + `withNetwork` + `networkMegabytesPerSecond` (decimal MB); `.networkIO` default (>5 MB/s, 5 s) via generalized sustained eval; `NettopMetricsSource` parses `nettop -P -L 1 -J …` CSV over `CommandRunner` (committed fixtures); `VitalsModel.poll()` now async, composes best-effort network rate onto each sample; net pill live + throughput chart |
| 5 | Energy / battery | ✅ Done | §1, §5 | Domain `VitalsReading.energyNanojoules` (`ri_energy_nj`, verified) + `MetricSample.energyWatts` (pure Δnj/Δns power estimate via extracted `rate`); `.battery` default (>5 W sustained 5 s) through generalized `sustainedAlert`; `EnergySource` port + `EnergyMeasurementError`; `PowermetricsSource` parses `powermetrics --samplers tasks --show-process-energy -f plist` (⚠️ synthesized fixture, needs live-root validation); `VitalsModel.measureEnergy()` on-demand measured read degrades to estimate; UI energy section (estimate W + Measure button + measured impact + honest degrade label), battery pill live, threshold row |
| 6 | Leaks (attach) | ✅ Done | §1, §3.1, §3.2, §4 | Domain `DiagnosticKind`/`DiagnosticRunner`/`DiagnosticResult`/`Finding`/`DiagnosticOptions`/`DiagnosticError`; `LeaksCLIRunner` (`leaks <pid>`) fully TDD'd vs real captured fixtures (0-leaks / with-stacks / no-stacks caveat / error); `XctraceDiagnosticRunner` records the verified Leaks trace + returns `.trace` path (export parser **deferred** — entitlement wall, chosen with user); `VitalsModel.checkLeaks()`/`recordLeakTrace()` + Leaks UI section (findings, MallocStackLogging caveat, Open in Instruments) |
| 7 | Zombies (relaunch) | ✅ Done | §1, §3.2, §3.3 | **No `Zombies` Instruments template/instrument exists** (verified) → pivoted to the §1-sanctioned mechanism: `ZombieDiagnosticRunner` relaunches the target via `/usr/bin/env NSZombieEnabled=YES <exe>` and parses the runtime's `message sent to deallocated instance` stderr into `Finding`s (real captured fixtures). `requiresRelaunch = true`; `Target.executablePath` added (threaded through discovery); `DiagnosticError.targetHasNoExecutablePath`. `VitalsModel.checkZombies()` + `canCheckZombies` (gated on runner **and** path); relaunch-honest Zombies UI in extracted `DeepDiagnosticsView`. Live relaunch validated in manual smoke. |
| 8 | Hitches & hangs | ✅ Done | §3.3 | Domain pure `DetectHangs` heuristic (stack series → `[Hang]`, consecutive run > 250 ms) + `StackSample`/`Hang`/`DiagnosticKind.hitches`; `SampleDiagnosticRunner` (verified same-UID `sample <pid>`, parses main-thread call tree → series → DetectHangs, real fixtures); `XctraceDiagnosticRunner` generalized to `.hitches`→`Time Profiler` (export deferred — entitlement wall); `spindump` **deferred** (needs root). `VitalsModel.checkHitches()`/`recordHitchTrace()` + Hitches & Hangs UI (honest sampling-hint caveat) |
| 9 | iOS device support | ⬜ Not started | §1 | dev-signed only |
| 10 | Session report & export | ⬜ Not started | §4 | — |
| 11 | Main window shell + live timeline | ⬜ Not started | §8 | Design handoff; honest live lanes only |
| 12 | Detection inbox + diagnostic detail | ⬜ Not started | §8 | Provenance-tagged feed (live alerts + deep findings) |
| 13 | Menu-bar companion (mini mode) | ⬜ Not started | §8 | Promoted from backlog |

Legend: ⬜ Not started · 🟦 In progress · ✅ Done · ⚠️ Blocked

## Known constraints / risks (live)
- `task_for_pid` needs debugger entitlement + same-UID; system procs out of scope. (SPEC §1)
- Zombies cannot be enabled on a running process — relaunch required. (SPEC §1, Slice 7)
- `powermetrics` needs root; energy degrades to the `ri_energy_nj` estimate otherwise. (SPEC §1, Slice 5)
- ⚠️ **The `powermetrics` plist fixture is synthesized from `man powermetrics`, not captured live** (capturing needs root; Latch never runs silent `sudo`). The `tasks`/`energy_impact` plist shape is an assumption that MUST be validated against a real privileged run in the manual integration smoke before the measured-energy path is trusted in production. (SPEC §6, §7; Slice 5)
- No privileged escalation path yet: `PowermetricsSource` runs through the plain `ProcessCommandRunner`, so measured energy only works if Latch itself runs as root; otherwise it degrades. An `SMAppService`/authorization helper is deferred. (SPEC §5, Slice 5)
- iOS limited to development-signed apps on connected devices. (SPEC §1, Slice 9)
- ⚠️ **The `xctrace` Leaks export parser is deferred.** `XctraceDiagnosticRunner` records the
  verified trace and returns its `.trace` path (open in Instruments) but does **not** parse
  `xctrace export` into `Finding`s. The deep `--attach` needs the debugger entitlement to
  acquire the task port — verified failing from the unentitled CLI ("Unable to acquire required
  task port"), so a real export fixture cannot be captured here, and the export XML schema is
  version-specific/undocumented. Validate + build the export parser from the entitled app in the
  manual smoke before relying on it. Slice 8 (Hitches, xctrace attach) hits the same wall.
  **Slice 7 (Zombies) does *not*** — it *launches* the target, which Latch owns, so no task-port
  entitlement is needed (and there is no Zombies template anyway). (SPEC §1, §6; Slice 6)
- **Zombies has no Instruments template/instrument** (verified macOS 26.2 / Xcode 16: absent from
  `xctrace list templates` and `list instruments`). Detection uses the §1 mechanism directly —
  relaunch under `NSZombieEnabled`, parse the runtime's stderr diagnostic. The actual live
  relaunch (spawning a fresh target instance, and bounding a target that never crashes — the
  current `ProcessCommandRunner` reads to EOF and would block on a long-lived relaunch) is
  **deferred to the manual integration smoke**; slice 7 TDDs the exact command + stderr parse
  against real captured fixtures via `FakeCommandRunner`. (SPEC §1, §6; Slice 7)
- The quick `leaks <pid>` path **does** attach to same-UID processes (it scans malloc zones
  without the full task port), so it works where `xctrace`'s deep attach needs the entitlement —
  it is Latch's reliable live leak-check path. Backtraces still require the target launched with
  `MallocStackLogging`; the UI says so when they're absent. (SPEC §1, Slice 6)
- Like `leaks`, the quick `sample <pid>` path **does** attach to same-UID processes **without
  root** (verified macOS 26.2: exit 0; missing process exits 255) — it is Latch's reliable
  hitch/hang look. **`spindump` is root-gated** (verified: "spindump must be run as root when
  sampling the live system"), so it is **deferred** like `powermetrics`. (SPEC §1, Slice 8)
- ⚠️ **The hitch/hang verdict from `sample` is an honest *hint*, not proof.** `sample`'s call
  tree reports per-frame counts that are "not necessarily consecutive" (per `man sample`), and a
  main thread legitimately parked in its run loop waiting for events presents the same as a hang.
  The runner reconstructs a stack series assuming within-leaf contiguity and only flags a wedged
  **leaf** (never high-count internal frames), but the deep `Time Profiler` `.trace` is the
  ground truth — surfaced as the on-demand action. A true sub-250 ms-resolution, no-entitlement
  *live* stall stream does not exist for an external process (per-sample stacks need the task
  port / a privileged helper), so hitch is a **deep-run signal**, not a live lane — the live pill
  stays `unavailable`. (SPEC §1, §3.3, §8; Slice 8)
- Local SwiftLint 0.59.1 `--strict` reports ~25 repo-wide violations (trailing_comma,
  identifier_name `i`/`n`, empty_count, static_over_final_class, optional_data_string_conversion)
  in files that landed lint-clean in earlier slices — a SwiftLint-version drift, **not** a
  slice-6 regression. Slice 6's new files add only convention-matching trailing commas (mirroring
  `PowermetricsSource` etc.). Worth a separate lint-baseline cleanup (pin the CI swiftlint version).
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
| 2026-06-26 | `EvaluateThresholds` dispatches per signal: *sustained* (all of trailing `window` breach) for CPU, *rising trend* (least-squares footprint slope → MB/min) for the leak hint | The two SPEC §3.3 thresholds have different shapes; one comparator can't express a trend. Slope-based rise detector fires on a real upward series and averages out noisy-flat (both TDD'd). Leak is an honest *hint*, not proof (SPEC §1) |
| 2026-06-26 | `Threshold.window` is a sample count (doubles as seconds at 1 Hz), not a `Duration` | `MetricSample` carries no timestamp yet; sample-count windows keep `EvaluateThresholds` pure/deterministic and align with the 1 Hz loop. Revisit if cadence becomes variable |
| 2026-06-26 | `Threshold.defaults` only covers `cpuSpike` + `memoryLeak`; UI pills mark the other four signals `unavailable` | No fake thresholds for capabilities that don't exist yet — zombies/hitch/network/energy get defaults as their slices land (SPEC §1) |
| 2026-06-26 | `Alert` omits `firedAt`; severity fixed to `.warning` this slice | Keeps Domain evaluation pure/deterministic (no clock); active alerts are recomputed from the live window each tick. `firedAt` + persistence arrive with session storage (slice 10); `critical` is reserved for tiered signals (energy, slice 5) (SPEC §4) |
| 2026-06-26 | Threshold overrides held in `VitalsModel` (per-target by construction), in-memory | One model per latched target, so per-model = per-target. SwiftData persistence of tuned thresholds deferred to the storage slice; not required by slice 3's test list |
| 2026-06-26 | Network modeled as its own `NetworkReading`→`NetworkRate` pair behind a `NetworkSource` port, mirroring `VitalsReading`→`MetricSample` | nettop is a separate, async (shell) backend from libproc; the adapter-per-source rule (SPEC §3.2) keeps it independently testable. The derived rate is then *composed onto* the existing `MetricSample` via `withNetwork`, so the unified §4 sample, the alert window, and `EvaluateThresholds` stay coherent on one type |
| 2026-06-26 | Network throughput in **decimal** MB/s (÷1_000_000), unlike footprint MiB | Network is universally quoted in decimal MB; the default threshold ("> 5 MB/s", SPEC §3.3) reads in those units. `networkMegabytesPerSecond` documents the divisor at the boundary |
| 2026-06-26 | `VitalsModel.poll()` became `async`; the libproc read stays authoritative for liveness, the nettop read is best-effort | Network genuinely needs async shell I/O. A transient `nettop` failure yields a zero rate for the tick rather than clobbering the target-exited error from libproc — death detection stays with the cheap kernel API |
| 2026-06-26 | `EvaluateThresholds` `sustainedAlert` parameterized with a value selector (Fowler: Parameterize Function); networkIO and cpuSpike share it | Both are "all-of-window breach" shapes differing only in the measured field (`cpuPercent` vs `networkMegabytesPerSecond`); one tested path, no duplication |
| 2026-06-26 | Per-tick `nettop -L 1` (one sample then exit), matching the PLAN command exactly | Verified on macOS 15.6: CSV logging mode emits raw integer byte counts, header `,bytes_in,bytes_out,` + one `name.pid,in,out,` row per match; `-x` makes no difference. `-L 1` blocks ~1 s, so the effective net cadence is ~2 s with the 1 s sleep — acceptable for a panel; a long-running streamed nettop is a future optimization |
| 2026-06-26 | Energy estimate uses `ri_energy_nj`, **not** SPEC's original `ri_billed_energy` (SPEC §3.1/§3.3 updated) | Verified on-machine (macOS 15.6) via `proc_pid_rusage(V6)`: `ri_energy_nj` is cumulative process energy in nanojoules — 1.4 J at start, 10.2 J after a CPU burn (grows with work). `ri_billed_energy` stayed ~0.1 mJ — it's cross-process *billing* (energy this proc caused others to spend), the energy analogue of `ri_billed_system_time`, not the proc's own energy. The skill itself flagged the field name as "confirm in the header" (SPEC §7). Power estimate = Δnj/Δns = W |
| 2026-06-26 | Energy alerting runs on the **estimate** (watts), always-available & single-unit; measured powermetrics impact is a display-only upgrade | Measured "energy impact" is a unitless proxy on a different scale from estimated watts; one `Threshold.value` can't sensibly compare both. SPEC §3.3 reads "'high' tier … *or* estimate slope" — the estimate slope (watts is the slope of cumulative energy) is the honest, consistent live signal. `.battery` reuses the generalized `sustainedAlert` (no new eval shape) |
| 2026-06-26 | Measured energy is an **on-demand** `VitalsModel.measureEnergy()`, not per-tick | `powermetrics` is heavy and root-gated — running it on the 1 Hz loop is wrong. The estimate rides every tick (free, from the same rusage call); the measured read is the SPEC §1 "deep run" mode, triggered by a user action, and degrades to the estimate (sets `energyMessage`) when unprivileged |
| 2026-06-26 | Slice 5 builds the parser + degrade + estimate; the privileged-escalation helper is deferred (chosen with the user) | `PowermetricsSource` sits behind `CommandRunner` so a future privileged runner (`SMAppService`/authorization) drops in without touching the adapter. The powermetrics plist fixture is **synthesized from `man powermetrics`** (root-only tool; no silent `sudo`) and flagged for live validation in the manual smoke (SPEC §6) — the `energy_impact` key name is an unverified assumption |
| 2026-06-26 | Slice 6 ships the `leaks` CLI runner fully; the `xctrace` Leaks **export parser is deferred** (chosen with the user) | The deep `xctrace record --attach` needs the `com.apple.security.cs.debugger` entitlement to acquire the task port — verified **failing** from the unentitled CLI ("Unable to acquire required task port"), so a real export fixture can't be captured here, and the `xctrace export` XML schema is version-specific/undocumented. Per SPEC §7 (verify-then-use) and §1 (no fake capabilities), `XctraceDiagnosticRunner` records the verified trace + returns the `.trace` path for Instruments; automated export parsing is validated in the manual smoke (SPEC §6). The `leaks <pid>` quick runner is the verifiable live path this slice — it attaches via malloc-zone scan without the task port |
| 2026-06-27 | Slice 7 pivots zombies off `xctrace`: **no `Zombies` template/instrument exists** in current Instruments, so a `ZombieDiagnosticRunner` relaunches under `NSZombieEnabled` instead (chosen with the user; SPEC §3.2/§3.3 updated first) | `xctrace list templates` and `xctrace list instruments` (macOS 26.2 / Xcode 16) carry **no** zombie entry — Apple removed the dedicated template. PLAN slice 7's literal `XctraceDiagnosticRunner(.zombies)` "under the Zombies template" is unbuildable. The underlying sanctioned mechanism SPEC §1 already describes is intact: `NSZombieEnabled` is a launch-time env var; relaunch the target and parse the Obj-C runtime's `*** -[Class sel]: message sent to deallocated instance 0x…` stderr line. This needs no `xctrace`, no template, and no debugger entitlement (launch, not attach) — and is fully fixture-testable. Per rule #1 SPEC was updated before building (SPEC §3.2 adapter table + note, §3.3 deep-diagnostic column) |
| 2026-06-27 | Slice 8: hitch/hang is a **deep-run signal**, not a live lane — verified there is no cheap, no-entitlement, sub-second per-sample main-thread stack stream for an external process | Per-sample stacks require the task port (`task_threads`+`thread_get_state`) — exactly what `sample`/`spindump`/Instruments do. `sample` is same-UID/no-root but yields an **aggregated** call tree (not a live stream); `spindump` needs root; `xctrace` attach needs the debugger entitlement. So unlike CPU/mem/net/energy, hitch has no cheap 1 Hz `MetricSample` value. The pure `DetectHangs` heuristic (the slice's required test) runs over a sampled stack series; the live pill stays `unavailable` (honest), and the signal surfaces only through the on-demand deep run. No `.hitch` entry in `Threshold.defaults` — the 250 ms bar lives in `DetectHangs` (SPEC §3.3/§8) |
| 2026-06-27 | Slice 8 ships the verified `sample` runner + `Time Profiler` trace; `spindump` deferred (root), `xctrace` export parse deferred (entitlement) — same pattern as slices 5/6 | Verified on-machine: `sample <pid> <s> <ms>` profiles same-UID **without root** (exit 0; gone → 255), `spindump` refuses without root. So `SampleSpindumpRunner` (SPEC §3.2) ships as `SampleDiagnosticRunner` (the `sample` path), `spindump` gated like `powermetrics`. `XctraceDiagnosticRunner` generalized by `DiagnosticKind` (`.leaks`→`Leaks`, `.hitches`→`Time Profiler`, both confirmed in `xctrace list templates`) to record the deep `.trace`; its `--attach` hits the same task-port wall as Leaks so export parsing is deferred to the manual smoke (§6). SPEC §3.2 note added first (rule #1) |
| 2026-06-27 | `DetectHangs` folds **consecutive** identical stacks (run > 250 ms, strict `>`); the `sample` parser reconstructs a series where each childless **leaf** → `count` copies of its root→leaf stack | A hang is a *consecutive* block, not total time in a stack (a periodic op revisiting a stack is not a hang). Keying on the childless **leaf** distinguishes a blocked spine (one leaf holds all samples — verified: `sleep` → `__semwait_signal` 92/92) from a busy thread whose **internal** frames accumulate high counts but whose leaves are short-lived (verified: Python compute → no leaf ≥ threshold). High-count internal frames never read as a stall. The reconstruction assumes within-leaf contiguity — the documented "honest hint" limitation. Both behaviours pinned by the `sample-hang`/`sample-responsive` real fixtures |
| 2026-06-27 | `Hang` modeled as its own Domain value (stack/sampleCount/`Duration`), not shoehorned into `Finding`; the runner maps `Hang`→`Finding` for the shared UI | A hang's salient datum is *duration*, which `Finding` (leak-centric: title/bytes/instances/backtrace) doesn't carry — overloading `byteCount`/`instanceCount` would mislead. `DetectHangs` returns `[Hang]` (clean, exactly testable against synthetic series); the Data runner converts to `DiagnosticResult`/`Finding` (`title`=leaf symbol, `instanceCount`=samples, `backtrace`=wedged stack) so the deep-run UI reuses the existing report rendering. (Fowler: keep the heuristic's type honest; map at the boundary) |
| 2026-06-27 | Env var injected via `/usr/bin/env NSZombieEnabled=YES <exe>`, not by extending `CommandRunner` | `CommandRunner.run(path, args:)` has no env channel; `/usr/bin/env` is the sanctioned, zero-API-surface way to set a launch-time env var, keeping the adapter behind the existing seam unchanged. Verified on-machine: the env var propagates and triggers the zombie; `env` exits **127** (`No such file or directory`) when it can't exec the binary — the runner's "couldn't relaunch" signal. The relaunch is **not** bounded by `options.timeLimit` (no flag applies); bounding a never-crashing target is a `ProcessCommandRunner` concern for the manual smoke |
| 2026-06-27 | `Target` grew `executablePath: String?` (threaded from `LibprocTargetDiscovery`, already read via `proc_pidpath`); zombie findings reuse `Finding` with `byteCount = 0` | Relaunch needs the on-disk binary path, which `Target` discarded (kept only the last component as `displayName`). Surfacing the path the discovery already reads is the thinnest change. `Finding` generalizes cleanly to a zombie message (title = `-[Class sel]`, instanceCount = times messaged, no bytes/stack — `MallocStackLogging` adds no backtrace to the stderr line, verified) rather than introducing a parallel value type (YAGNI). Exit handling differs from leaks: a zombie aborts the process (`SIGTRAP`, exit 133) — that abnormal exit is the *expected* signal, so the runner parses findings regardless of exit code and only throws on `env`'s 126/127 launch failure |
| 2026-06-27 | `isRunningLeakDiagnostic` renamed to `isRunningDiagnostic` (Fowler: Rename Field); leaks + zombies UI extracted into `DeepDiagnosticsView` (Fowler: Extract Class) on the refactor step | The busy flag is now shared by leak + zombie + trace actions, so the leak-specific name misled. Adding the zombies section pushed `VitalsView` past SwiftLint's `type_body_length` (269 > 250) and `file_length` (410 > 400) — a real SRP smell: the view mixed live-polling charts with on-demand deep-run UI. Extracting the two deep-run sections (+ shared `reportSummary`/`caveat`, via Extract Function) into `DeepDiagnosticsView` restored both limits and the single responsibility; `import AppKit` (only `NSWorkspace`, which moved) dropped from `VitalsView` |
| 2026-06-26 | `leaks` text parsing lives in the Data adapter (`LeaksCLIRunner`); findings come from `STACK OF` groups when backtraces exist, else from flat `ROOT LEAK:` lines | `leaks` output differs with/without launch-time `MallocStackLogging` (both shapes captured live on macOS 26.2 / Xcode 16 as committed fixtures): grouped stacks (title + instance count + backtrace + group bytes) vs address-only blocks. `DiagnosticResult.hasBacktraces` (a finding carries a stack) drives the UI's MallocStackLogging caveat. Exit codes 0 (none) and 1 (found) both parse; >1 throws `DiagnosticError.toolFailed` (verified vs `man leaks`) |
| 2026-06-26 | Regex literals in `LeaksCLIRunner` are declared **function-local**, not `static let` | Swift 6 strict concurrency: `Regex` is not `Sendable`, so a shared `static let` Regex is a `#MutableGlobalVariable` concurrency error. Each pattern is used in one place, so a local `let` is both correct and clean |
| 2026-06-26 | `VitalsModel` stores the full `Target` (optional) alongside `pid` for the deep runners | `DiagnosticRunner.run(_:options:)` attaches by `Target` (SPEC §3.1) while live polling needs only `pid`; adding an optional `target` is the thinnest change that keeps the existing pid-based polling tests untouched. `runDiagnostic` extracted (Fowler: Extract Function + Parameterize Function) so `checkLeaks`/`recordLeakTrace` differ only in which fields they write — same move as slice 4's `sustainedAlert` |
| 2026-06-26 | Adopt `design_handoff_latch_profiler/` as the authoritative UI/visual spec (hi-fi) — recorded as SPEC §8; redesign scheduled as PLAN slices 11–13 (chosen with the user) | The handoff has sat in the repo since the initial scaffold commit but was never referenced by SPEC/PLAN/PROGRESS/CLAUDE, and the UI built across slices 1–6 is a minimal functional dashboard, not the handoff. Per rule #1 (spec-driven), SPEC is updated first. The redesign is sequenced **after** the data slices it visualizes (timeline lanes ← slices 2/4/5/8; detection inbox ← slices 6–8/10), so it lands as slices 11 (main window + live timeline), 12 (detection inbox + diagnostic detail), 13 (menu-bar companion, promoted from backlog). The prototype fakes all data; SPEC §8 carries a **binding** reconciliation where the handoff conflicts with §1 honest constraints — §1 wins: no live zombie lane (relaunch-only), Frame-time is a hint/deep run not a live counter, energy live lane is the watts estimate, symbolicated call trees/stacks are on-demand deep-run output (provenance shown per card), iOS is dev-signed-device-only and watchOS is out of scope, and live sampling stays ~1 Hz (faster canvas redraw is presentation-only) |

## Changelog
- 2026-06-27 — **Slice 8 (Hitches & hangs) landed.** Verification first (golden rule #4)
  established the honest shape: `sample <pid> <s> <ms>` profiles a same-UID process **without
  root** (exit 0; missing process → 255) — Latch's verified hitch/hang quick look — whereas
  `spindump` refuses without root ("must be run as root when sampling the live system") so it is
  **deferred** (root-gated like `powermetrics`), and the deep `Time Profiler` template (confirmed
  in `xctrace list templates`) records via `xctrace` but its `--attach` hits the same
  debugger-entitlement task-port wall as Leaks (export parse **deferred**). Because per-sample
  main-thread stacks need the task port, **hitch is a deep-run signal, not a live lane** — the
  live pill stays `unavailable` (honest), no `.hitch` in `Threshold.defaults`. Domain: pure
  `DetectHangs` use case (`StackSample` series → `[Hang]`; flags maximal *consecutive* runs of an
  unchanged stack lasting **strictly > 250 ms** at the sampling interval — SPEC §3.3) plus
  `StackSample`, `Hang` (stack/sampleCount/`Duration`), and `DiagnosticKind.hitches`. Data:
  `SampleDiagnosticRunner` (behind `CommandRunner`) runs the verified `sample` command, locates
  the `com.apple.main-thread` block, reconstructs a stack series from its call tree (each childless
  **leaf** → `count` copies of its root→leaf stack — so a wedged spine flags but high-count
  *internal* frames of a busy thread don't), runs `DetectHangs`, and maps `[Hang]`→`DiagnosticResult`;
  `XctraceDiagnosticRunner` generalized by `DiagnosticKind` to also record the `Time Profiler`
  trace. Presentation: `VitalsModel.checkHitches()` + `recordHitchTrace()` (reusing the shared
  `runDiagnostic` helper) + `canCheckHitches`/`canRecordHitchTrace`; a "Hitches & Hangs" section in
  `DeepDiagnosticsView` with the honest sampling-hint caveat ("a main thread idling in its run loop
  looks similar; the Time Profiler trace is the ground truth"). TDD red-first: Domain
  `DetectHangsTests` (flags >250 ms block / ignores responsive / strict-`>` boundary at 250 ms /
  consecutive-not-total / distinct blocks / empty); Data `SampleDiagnosticRunnerTests` (kind+relaunch
  / exact `sample` command / parses wedge→hang vs responsive→no-hang / exit-255 throws / no-pid)
  against **real captured** fixtures (`sample-hang` = `sleep` wedged in `__semwait_signal`;
  `sample-responsive` = Python compute, branching, no wedged leaf); Data `XctraceDiagnosticRunnerTests`
  gained the Time Profiler case; Presentation `VitalsModelHitchCheckTests` (report stored / failure
  message / trace path / availability). Refactor on green: Replace Tuple with Object (`FrameNode`,
  clearing SwiftLint `large_tuple`) + Extract Function (shared `findingRow` unifying the leak/hitch/
  zombie finding rows). `swift test` green (76/76), `xcodebuild test` green (app + UI), zero
  compiler/concurrency warnings; new files lint-clean (only the documented repo-wide `trailing_comma`
  drift, matched to the sibling adapters' convention).
  ⚠️ The hitch verdict from `sample` is an honest **hint** (counts aren't guaranteed consecutive; an
  idle run-loop wait reads the same) — the `Time Profiler` `.trace` is ground truth, validated in the
  manual smoke; `spindump` (root) and the `xctrace` export parser remain deferred. See the slice-8
  decision log + live-risk notes.
- 2026-06-27 — **Slice 7 (Zombies — deep, relaunch only) landed.** Verification first
  (golden rule #4) surfaced a spec-level fact: **there is no `Zombies` Instruments
  template *or* instrument** in current Xcode (macOS 26.2 / Xcode 16 — absent from both
  `xctrace list templates` and `xctrace list instruments`), so PLAN slice 7's literal
  `XctraceDiagnosticRunner(.zombies)` "under the Zombies template" is unbuildable. Pivoted
  (with the user) to the mechanism SPEC §1 already mandates — relaunch under `NSZombieEnabled`
  — and updated SPEC §3.2/§3.3 first (rule #1). Domain: `DiagnosticKind.zombies`,
  `Target.executablePath`, `DiagnosticError.targetHasNoExecutablePath`. Data:
  `ZombieDiagnosticRunner` (behind `CommandRunner`) relaunches via `/usr/bin/env
  NSZombieEnabled=YES <exe>` and parses the Obj-C runtime's `*** -[Class sel]: message sent
  to deallocated instance 0x…` stderr lines into `Finding`s (grouped by signature; no
  bytes/stack — `MallocStackLogging` adds none to that line); a zombie aborts the target
  (`SIGTRAP`/exit 133) which is the *expected* signal, so findings parse regardless of exit and
  only `env`'s 126/127 launch failure throws. `executablePath` now rides every `Target` from
  `LibprocTargetDiscovery`. Presentation: `VitalsModel.checkZombies()` (reusing the shared
  `runDiagnostic` helper) + `canCheckZombies` (gated on runner **and** an executable path to
  relaunch); a relaunch-honest Zombies UI ("can't attach — NSZombieEnabled is read at launch;
  this relaunches a fresh instance"). TDD red-first: Data `ZombieDiagnosticRunnerTests`
  (requiresRelaunch true / exact `/usr/bin/env` command / parses real zombie stderr into a
  finding / clean run → no zombies / `env` exit 127 throws / missing path throws) against
  **real captured** fixtures (`zombie-detected`, `zombie-none`, `zombie-launch-failed`);
  discovery test asserts `executablePath`; Presentation `VitalsModelZombieCheckTests` (report
  stored / failure message / availability needs runner + path) via a now-configurable
  `FakeDiagnosticRunner`. Refactor on green: Rename Field (`isRunningLeakDiagnostic` →
  `isRunningDiagnostic`, now shared) + Extract Class (leaks + zombies UI → `DeepDiagnosticsView`,
  resolving `VitalsView`'s `type_body_length`/`file_length` and an SRP smell) + Extract Function
  (`reportSummary`). `swift test` green (63/63), `xcodebuild test` green (app + UI), zero
  compiler/concurrency warnings; new presentation files lint-clean.
  ⚠️ The actual live relaunch (spawning a fresh target instance, and bounding a target that
  never crashes) is **deferred to the manual integration smoke** — see the slice-7 decision log
  + live-risk note; the slice TDDs the command + parse against captured fixtures.
- 2026-06-26 — **Design handoff acknowledged (docs only, no code).** Adopted
  `design_handoff_latch_profiler/` (`README.md` + `Latch.dc.html`) as the authoritative
  hi-fi UI/visual spec: added **SPEC §8** (two surfaces — main window + menu-bar companion —
  plus a *binding* live-vs-deep reconciliation table that subordinates the faked prototype
  stream to the §1 honest constraints), added **PLAN slices 11–13** (main window + live
  timeline · detection inbox + diagnostic detail · menu-bar companion, the last promoted out
  of the backlog), and logged the adopt decision + constraint deltas. No production code
  changed; the redesign is sequenced after the data slices it visualizes.
- 2026-06-26 — **Slice 6 (Leaks — deep, on-demand attach) landed.** Domain gained the deep-run
  vocabulary: `DiagnosticKind` (`.leaks` only — others land with their slices), the
  `DiagnosticRunner` port (`kind`/`requiresRelaunch`/`run(_:options:)`), `DiagnosticResult`
  (`summary` + `[Finding]` + optional `tracePath`, with `hasBacktraces`/`hasFindings`), `Finding`
  (title / byteCount / instanceCount / backtrace), `DiagnosticOptions` (`timeLimit`), and
  `DiagnosticError` (`.toolFailed`/`.targetHasNoPID`). Data gained two adapters behind
  `CommandRunner`: `LeaksCLIRunner` runs `leaks <pid>` and parses the real output — grouped
  `STACK OF … INSTANCES OF '…'` blocks (with backtraces) when MallocStackLogging is set, flat
  `ROOT LEAK:` blocks otherwise — into findings, treating exit 0/1 as parseable and >1 as a
  thrown tool error; `XctraceDiagnosticRunner` runs the **verified** `xcrun xctrace record
  --template Leaks --attach <pid> --time-limit Ns --output <…>.trace` and returns the `.trace`
  path. Presentation: `@MainActor @Observable VitalsModel` gained on-demand `checkLeaks()` and
  `recordLeakTrace()` (shared `runDiagnostic` helper, busy flag, honest failure messages) plus
  `canCheckLeaks`/`canRecordTrace`; `VitalsView` gained a Leaks section — "Run Leak Check"
  (findings list + summary + the MallocStackLogging caveat when backtraces are absent) and
  "Record Trace" → "Open in Instruments". TDD red-first: Domain `DiagnosticResultTests`
  (hasBacktraces / hasFindings); Data `LeaksCLIRunnerTests` (no-leaks / grouped-with-backtraces /
  no-stacks caveat / exit>1 throws / exact command / no-pid) against **real captured, sanitized**
  fixtures (`leaks-none`, `leaks-with-stacks`, `leaks-without-stacks`); Data
  `XctraceDiagnosticRunnerTests` (exact command + trace path / attach-failure throws /
  requiresRelaunch false); Presentation `VitalsModelLeakCheckTests` (report stored / failure
  message / trace path / availability) via `FakeDiagnosticRunner`. Refactor on green: Extract
  Function + Parameterize Function (`runDiagnostic`), regex literals made function-local for
  Swift 6 `Sendable`. `swift test` green (57/57), `xcodebuild test` green (app + UI), zero
  compiler/concurrency warnings.
  ⚠️ The `xctrace` Leaks **export parser is deferred** (entitlement wall blocks capturing a real
  export fixture; schema is version-specific) — see the slice-6 decision log + live-risk note;
  build + validate it from the entitled app in the manual smoke. Slices 7/8 hit the same wall.
- 2026-06-26 — **Slice 5 (Energy / battery) landed.** Domain: `VitalsReading` grew
  `energyNanojoules` (`ri_energy_nj`, verified on-machine as cumulative process energy that
  grows with CPU work — chosen over SPEC's original `ri_billed_energy`, which is cross-process
  billing; SPEC §3.1/§3.3 updated). `MetricSample` grew `energyWatts`, computed in
  `derive` as the per-nanosecond energy delta (nj/ns = W) via a new extracted `rate(counter:)`
  helper now shared with `cpuPercent` (Fowler: Extract Function + Parameterize Function).
  `Threshold.defaults` added `.battery` (> 5 W sustained 5 s — a labelled starting point) and
  `EvaluateThresholds` fires it through the existing generalized `sustainedAlert` measuring
  `energyWatts`. New `EnergySource` port + `EnergyMeasurementError` (`.unavailable` /
  `.processNotFound`). Data: `PowermetricsSource` runs `powermetrics --samplers tasks
  --show-process-energy -f plist -n 1 -i 1000` through `CommandRunner` and parses the tasks
  plist (`PropertyListSerialization`, strips trailing NUL) for the pid's `energy_impact`; a
  non-zero exit (unprivileged) throws `.unavailable`. `LibprocMetricsSource` now fills
  `energyNanojoules`. Presentation: `VitalsModel` gained the on-demand `measureEnergy()`
  (stores `measuredEnergy`, or degrades — `measuredEnergy` nil + `energyMessage` — on failure)
  plus `canMeasureEnergy`; the watts estimate already rides each derived sample. `VitalsView`
  gained an energy section (estimate W + "Measure energy" button + measured impact + honest
  degrade label), the now-live battery pill, the battery alert banner, and a battery threshold
  row. TDD red-first: Domain `MetricSampleTests` (watts exact / zero-interval / rewind) +
  `EvaluateThresholdsTests` (battery sustained fires/not, defaults cover battery); Data
  `PowermetricsSourceTests` (parse impact, pid-not-found, non-zero-exit `.unavailable`, exact
  command) against a synthesized `Fixtures/powermetrics-tasks.plist`; `LibprocMetricsSourceTests`
  asserts live energy > 0; Presentation `VitalsModelTests` (estimate attached, measured stored,
  degrade path). Refactor on green: Extract Function `rate(counter:)`. `swift test` green
  (45/45), `xcodebuild test` green (app + UI), zero code warnings.
  ⚠️ The powermetrics fixture is synthesized from `man powermetrics`, not captured live — see
  the slice-5 decision log + live-risk note; validate against a real root run in the manual smoke.
- 2026-06-26 — **Slice 4 (Network I/O) landed.** Domain gained the raw `NetworkReading`
  (cumulative bytes_in/out + monotonic stamp), the derived `NetworkRate` with the pure
  `NetworkRate.derive(from:to:)` byte-delta-over-wall-clock math (guards zero-interval and
  counter rewind), and the `NetworkSource` port. `MetricSample` grew `netInBytesPerSec`/
  `netOutBytesPerSec` (default 0), a `withNetwork(_:)` composer, and the
  `networkMegabytesPerSecond` (decimal MB/s) the threshold reads. `Threshold.defaults`
  added `.networkIO` (> 5 MB/s sustained 5 s) and `EvaluateThresholds` now fires it via a
  `sustainedAlert` generalized with a value selector (shared with cpuSpike). Data gained
  `NettopMetricsSource` — runs the exact PLAN command `nettop -P -L 1 -J bytes_in,bytes_out
  -p <pid>` through `CommandRunner` and sums the CSV data rows (header/blank lines skipped
  because their byte fields aren't numbers); verified against live macOS 15.6 output.
  Presentation: `VitalsModel.poll()` is now `async` and composes a best-effort network rate
  onto each derived sample (a nettop failure degrades to a zero rate without clobbering the
  libproc liveness error); `VitalsView` got a network header stat, a purple throughput
  chart, a live network status pill, a network-alert banner, and a network row in the
  threshold popover. TDD red-first: Domain `NetworkRateTests` (rate from deltas, time
  scaling, zero-interval + rewind guards) + `MetricSample` net tests + `EvaluateThresholds`
  networkIO (fires sustained / not on a burst) + defaults; Data `NettopMetricsSourceTests`
  (parse traffic row, header-only → 0, multi-row sum, exact-command pin) against committed
  `Fixtures/`; Presentation `VitalsModelTests` (rate attached from consecutive readings,
  sustained-network alert). Refactor on green: Parameterize Function on `sustainedAlert`,
  Extract Function `latest(_:)` removing the repeated header-formatting pattern. `swift
  test` green (36/36), `xcodebuild test` green (app + UI), zero code warnings.
- 2026-06-26 — **Slice 3 (Thresholds & alerting) landed.** Domain gained `Comparator`
  (pure `matches`), `Threshold` (signal/comparator/value/window + `defaults` for the
  live signals), `Alert`/`AlertSeverity`, and the pure `EvaluateThresholds` use case:
  CPU spike fires when *all* of the trailing `window` samples breach (sustained); the
  memory-leak hint fires when the least-squares slope of footprint over the window,
  projected to MB/min, breaches (rising trend, ignores noisy-flat). Presentation:
  `VitalsModel` now recomputes active `alerts` from its ring buffer each tick and
  exposes `updateThreshold(_:value:)` for per-target tuning; `VitalsView` gained a
  six-signal status-pill strip (honest `unavailable` for signals with no live indicator
  yet — SPEC §1), red alert banners, and a threshold-tuning popover
  (`ThresholdSettingsView`). TDD red-first: Domain `ComparatorTests` (four comparators)
  + `EvaluateThresholdsTests` (sustained fires/not-sustained/trailing-window/needs-full-
  window; leak fires-on-rising / ignores-noisy-flat; defaults cover live signals);
  presentation `VitalsModelTests` (alert fires on sustained high CPU, none below
  threshold, tuning retunes). Refactor on green: named `Window` struct + guarded
  bindings replaced the tuple/force-unwraps (lint `force_unwrapping: error`), lines
  ≤110. `swift test` green (24/24), `xcodebuild test` green, zero warnings.
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
