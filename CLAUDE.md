# CLAUDE.md — Latch

Operating contract for Claude Code on this repo. Read this, then `SPEC.md`, then the
current slice in `PLAN.md`, before writing anything.

## What this is
A native macOS app that latches onto a running same-UID macOS process (or a
development-signed iOS app on a connected device) and surfaces six health signals:
memory leaks, zombies, hitches/hangs, CPU spikes, network I/O, battery/energy.
Stack: Swift 6 (strict concurrency), SwiftUI, Clean Architecture, SwiftData. It is a
**GUI orchestrator over sanctioned Apple tooling** (libproc, mach, `xctrace`,
`powermetrics`, `nettop`, `devicectl`) — not a re-implementation of Instruments.

## The golden rules
1. **Spec-driven.** `SPEC.md` is truth. If a slice needs something not in the spec,
   update the spec first (and note it in `PROGRESS.md` decision log), then build.
2. **TDD, always — non-negotiable.** ALWAYS use TDD when adding ANY new feature or
   behavior. Red → green → refactor: write the failing test FIRST, watch it fail, then
   write the thinnest production code to pass. No production code — not even one line —
   without a failing test that required it. This applies to every feature, bug fix, and
   adapter; no exceptions. (skill: `tdd`)
3. **One slice at a time.** Follow `PLAN.md` in order. Finish and mark ✅ in
   `PROGRESS.md` before starting the next. Keep each slice end-to-end and demoable.
4. **Never trust memory for Apple APIs.** Before implementing any adapter, consult the
   relevant skill and verify every API/flag/template against current official docs,
   man pages, or `xctrace list templates` / `xcrun devicectl`. Memory is stale; the
   docs skills exist to force verification. (skills: `apple-process-metrics`,
   `instruments-xctrace`, `code-signing-entitlements`, `macos-apple-docs`, `ios-apple-docs`)
5. **No fake capabilities.** Respect `SPEC.md §1` constraints. If something can't be
   done (zombies on a running process, profiling App Store apps, energy without root),
   the code says so and the UI says so. Do not paper over limits.
6. **Clean Architecture boundaries.** Domain imports nothing. Adapters never leak
   `Process`, `mach_*`, or C-interop types past the Data boundary. (skill: `clean-code`)
7. **Refactor on green — always consult the skills.** ALWAYS consult the
   `refactoring-fowler` skill before and during ANY refactoring. After tests pass, apply
   a NAMED Fowler refactoring (never ad-hoc rewrites) in tiny behavior-preserving steps
   under green tests; commit refactors separately from behavior changes. (skill: `refactoring-fowler`)
   Every red → green → refactor cycle MUST end with `clean-code`-clean code: consult the
   `clean-code` skill on the refactor step and do not consider a cycle done until naming,
   function size, SRP, and boundaries pass that bar. (skill: `clean-code`)
8. **Concurrency hygiene.** No data races; actors/`Sendable` correct; zero new strict-
   concurrency warnings. (skill: `swift6-concurrency-swiftui`)

## The slice loop (per slice)
1. Read the slice in `PLAN.md` + its `SPEC.md` refs.
2. Write the failing test(s) named in the slice.
3. Implement the thinnest code to pass — behind the right protocol/adapter.
4. Refactor; keep tests green; remove duplication.
5. Verify against docs anything API-level you touched.
6. Update the slice row + changelog + (if needed) decision log in `PROGRESS.md`.
7. Stop. Do not bleed into the next slice.

## Definition of Done (every slice)
- Spec ref recorded · failing test written first · green · refactored ·
  zero new warnings (compiler + strict concurrency + lint) · adapters testable via
  fakes · `PROGRESS.md` updated · `SPEC.md §1` constraints honored in code **and** UI.

## File map
```
SPEC.md       — technical truth (architecture, constraints, signals, data model)
PLAN.md       — vertical slices 0–10
PROGRESS.md   — status table, decision log, changelog, live risks
CLAUDE.md     — this file
.claude/skills/ — installed, auto-triggerable skills (see table below)
  clean-code/ tdd/ refactoring-fowler/ macos-apple-docs/ ios-apple-docs/
  apple-process-metrics/ instruments-xctrace/ code-signing-entitlements/
  swift6-concurrency-swiftui/
```

## Skills — when each fires
| Skill | Consult when… |
|---|---|
| `clean-code` | naming, function size, boundaries, dependency direction, any "is this clean?" moment |
| `tdd` | starting any slice — before writing production code |
| `refactoring-fowler` | the green step; cleaning up duplication/structure with a named refactoring |
| `apple-process-metrics` | building libproc / mach / rusage / nettop / powermetrics adapters |
| `instruments-xctrace` | building any `xctrace`/`leaks`/`sample`/`spindump` diagnostic runner |
| `code-signing-entitlements` | entitlements, hardened runtime, notarization, SIP, privilege escalation |
| `macos-apple-docs` | AppKit/SwiftUI-on-mac, system frameworks, verifying mac APIs |
| `ios-apple-docs` | iOS attach constraints, devicectl, MetricKit, verifying iOS APIs |
| `swift6-concurrency-swiftui` | actors, `Sendable`, `@Observable`, async sampling loops |

## Commits
Conventional commits. Separate behavior changes from refactors. Reference the slice
(`feat(slice-2): live cpu+memory polling`). Never commit secrets, provisioning
profiles, or `.trace` bundles.

## Out of scope (do not build, do not fake)
System/other-user processes · App Store iOS apps · jailbreak/SIP-off paths ·
re-implementing the Instruments trace viewer · cross-platform targets.
