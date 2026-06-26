# PROGRESS — Latch

Single source of truth for state. Update the slice row **before** moving on. Append
to the decision log when a non-obvious choice is made. Never delete history.

## Slice status

| # | Slice | Status | Spec ref | Notes |
|---|---|---|---|---|
| 0 | Scaffold & guardrails | ✅ Done | §3, §5 | LatchKit SPM pkg (Domain/Data), CommandRunner + fake, debugger entitlement, Swift 6, CI+lint |
| 1 | Discover & pick local target | ⬜ Not started | §3.2 | — |
| 2 | Live vitals (mem + CPU) | ⬜ Not started | §3.3 | — |
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

## Changelog
- 2026-06-26 — **Slice 0 (Scaffold & guardrails) landed.** Local SwiftPM package
  `LatchKit` with `LatchDomain` (`SignalKind`) and `LatchData` (`CommandRunner`,
  `CommandResult`, `ProcessCommandRunner`) layers; App target links both products.
  TDD: `SignalKindTests` (Domain builds with zero outward imports) and
  `CommandRunnerTests` (fake returns canned stdout; real runner captures `/bin/echo`)
  written red-first, now green. App on Swift 6 strict concurrency, App Sandbox OFF,
  Hardened Runtime ON, `com.apple.security.cs.debugger` entitlement (verified in the
  signed binary). SwiftLint config + GitHub Actions CI (package tests · app build ·
  lint). `swift test` green (3/3), `xcodebuild` BUILD SUCCEEDED with zero warnings.
