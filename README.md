# Latch

A native **macOS** app that latches onto a running process — a local macOS app, or a
development-signed iOS app on a connected device — and surfaces six health signals:

> **memory leaks · zombies · hitches/hangs · CPU spikes · network I/O · battery/energy**

Latch is a SwiftUI / Swift 6 / Clean Architecture **GUI orchestrator over sanctioned
Apple tooling** (`libproc`, `mach`, `xctrace`, `powermetrics`, `nettop`, `devicectl`).
It launches and summarizes the same mechanisms Instruments, Activity Monitor, `leaks`,
and `powermetrics` already use — it does **not** re-implement the Instruments trace
viewer, and it never takes an unsanctioned attach path.

## The six signals

| Signal | Live indicator | Deep diagnostic |
|---|---|---|
| Memory leak | `ri_phys_footprint` trend | `xctrace` Leaks (attach) |
| Zombies | — (not detectable live) | `xctrace` Zombies (**relaunch only**) |
| Hitch / hang | main-thread stall heuristic | Time Profiler / `spindump` / `sample` |
| CPU spike | CPU% from rusage time deltas | Time Profiler |
| Network I/O | `nettop` bytes in/out rate | `xctrace` Network |
| Battery / energy | `ri_billed_energy` estimate; `powermetrics` if root | `xctrace` Energy Log |

Each signal runs in **two modes**: cheap **live polling** for at-a-glance dashboards
and threshold alerting, and **on-demand deep runs** for root-causing. The UI never
conflates the two.

## Honest constraints

Latch is not magic. Building a profiler means living inside hard limits, and the code
is written so no feature can quietly pretend otherwise (see `SPEC.md §1`):

- **Same-UID only.** `task_for_pid` needs the `com.apple.security.cs.debugger`
  entitlement and hardened-runtime signing, and works only for your own UID's
  processes. System / other-user / SIP-protected processes are out of scope.
- **Zombies require relaunch.** `NSZombieEnabled` is a launch-time environment
  variable — it can't be enabled on an already-running process.
- **Energy needs root.** Per-process `powermetrics` requires a user-initiated
  privilege escalation; declining degrades to the cheaper rusage estimate.
- **iOS is dev-signed only.** Only development-signed apps on a connected, unlocked,
  paired device. App Store apps cannot be profiled.

## Architecture

Clean Architecture, three layers, dependency rule points inward. Each metric backend
is a swappable, individually-testable **adapter**.

```
Presentation (SwiftUI)      Views, @Observable view models, charts, alert banners
        │ depends on
Domain (pure Swift, no I/O) Entities + UseCases. Owns the protocol abstractions.
        ▼ abstractions only
Data (adapters + I/O)       MetricsSource / DiagnosticRunner / TargetDiscovery impls
```

The pure layers live in a local SwiftPM package, **`LatchKit`**, split into
`LatchDomain` (no outward imports) and `LatchData` (adapters behind a `CommandRunner`
protocol). The app target links both products. This enforces the dependency rule
structurally and lets the pure layers run under `swift test` in CI without Xcode.

## Build & test

```bash
# Pure Domain + Data layers (no Xcode needed)
cd LatchKit && swift test

# Full app (Swift 6 strict concurrency, hardened runtime, debugger entitlement)
xcodebuild -project Latch.xcodeproj -scheme Latch build

# Lint
swiftlint
```

Latch ships **non-sandboxed, hardened-runtime, notarized** with a single entitlement,
`com.apple.security.cs.debugger` — the sandbox is incompatible with `task_for_pid` on
arbitrary same-UID pids.

## Project layout

```
SPEC.md       Technical truth — start with §1, the honest constraints
PLAN.md       Vertical slices 0–10
PROGRESS.md   Status table, decision log, changelog, live risks
CLAUDE.md     How the agent works on this repo (golden rules, slice loop, DoD)
LatchKit/     SwiftPM package: LatchDomain + LatchData (+ tests)
Latch/        SwiftUI app target
LatchTests/   App unit tests
LatchUITests/ App UI tests
.claude/skills/  Installed, verify-then-use skills
```

## How it's built

Spec-driven and test-first. `SPEC.md` is the source of truth; `PLAN.md` slices it into
end-to-end deliverables; every slice is red → green → refactor under TDD. Apple APIs
are verified against current docs / man pages / `xctrace list templates` rather than
trusted from memory.

## Status

Slice 0 (scaffold & guardrails) is done: `LatchKit` package, `CommandRunner` adapter +
fake, Swift 6 strict concurrency, debugger entitlement, CI + lint, all tests green.
Slice 1 (discover & pick a local target) is next. See `PROGRESS.md` for the live table.
