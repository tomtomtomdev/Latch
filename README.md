# Latch

A native macOS app that latches onto a running process — a local macOS app, or a
development-signed iOS app on a connected device — and surfaces six health signals:
**memory leaks, zombies, hitches/hangs, CPU spikes, network I/O, and battery/energy.**

It's a SwiftUI / Swift 6 / Clean Architecture GUI orchestrator over sanctioned Apple
tooling (libproc, mach, `xctrace`, `powermetrics`, `nettop`, `devicectl`) — not a
re-implementation of Instruments.

## Read in this order
1. `CLAUDE.md` — how the agent works on this repo (golden rules, slice loop, DoD).
2. `SPEC.md` — technical truth: **start with §1, the honest constraints.**
3. `PLAN.md` — vertical slices 0–10.
4. `PROGRESS.md` — status table, decision log, changelog, live risks.

## Skills (`skills/`)
Engineering: `clean-code`, `tdd`, `refactoring-fowler`, `swift6-concurrency-swiftui`.
Domain: `apple-process-metrics`, `instruments-xctrace`, `code-signing-entitlements`,
`macos-apple-docs`, `ios-apple-docs`.

Each is a standard `SKILL.md` (name + description frontmatter, then body), installable
into Claude Code. The two `*-apple-docs` skills are deliberately verify-then-use: they
exist to stop the agent trusting stale recalled Apple APIs.

## The one thing to internalize
Latch lives inside hard limits (debugger entitlement + same-UID only; zombies need
relaunch; energy needs root; iOS only profiles dev-signed apps). The kit is written so
no slice can quietly pretend otherwise — see `SPEC.md §1`.
