---
name: tdd
description: Drive development test-first using red-green-refactor for the Latch project. Use this skill at the start of every slice and before writing any production Swift code — covers what test to write first, how to test Clean Architecture layers, how to test shell/system adapters with fakes and recorded fixtures, and Swift Testing / XCTest conventions. Pushy trigger: invoke this whenever you are about to write implementation code, even a small function.
---

# Test-Driven Development (Latch)

No production code without a failing test that demanded it. The cycle is short and
non-negotiable: **Red → Green → Refactor.**

## The cycle
1. **Red.** Write the smallest test that fails for the right reason (assert behavior,
   then watch it fail — a test that passes immediately tested nothing).
2. **Green.** Write the minimum code to pass. Hardcoding is allowed at first;
   triangulate with a second test to force generality.
3. **Refactor.** With tests green, remove duplication and improve names/structure
   (hand off to `refactoring-fowler`). Tests stay green throughout.

Three laws: don't write production code except to pass a failing test; don't write
more of a test than is sufficient to fail; don't write more production code than is
sufficient to pass.

## What to test first, per layer
- **Domain (the bulk of tests).** Pure, fast, deterministic. Test use cases and
  heuristics directly: CPU% delta math, the memory-leak rise detector, threshold
  comparators, byte-delta → rate, report serialization. No I/O, no clock, no shell.
- **Data adapters.** Put every shell/system call behind a protocol (`CommandRunner`,
  injectable clock). Test the **parser** against **recorded real output** committed
  in `Fixtures/` (e.g. `nettop`, `xctrace export`, `leaks`, `devicectl` JSON). The
  adapter under test reads canned stdout from a `FakeCommandRunner` — never the real OS.
- **Presentation.** View-model tests with `Fake` sources; assert published state
  transitions. Snapshot tests optional, not load-bearing.

## Testing rules of thumb
- Inject time and randomness. A sampling loop takes a clock; tests advance it.
- One logical assertion per test; name tests as behavior:
  `cpuPercent_isExact_forSyntheticTimeDeltas()`.
- Arrange-Act-Assert, visibly separated.
- Fast (Domain suite in milliseconds) and isolated (no shared mutable state, no order
  dependence). Async tests use structured concurrency, not sleeps.
- F.I.R.S.T.: Fast, Independent, Repeatable, Self-validating, Timely.

## Fixtures discipline
Capture real tool output once, sanitize (strip usernames/paths/pids to placeholders),
commit under `Fixtures/<tool>/<case>.txt|json`. Each fixture documents the command and
OS version that produced it (Apple changes output formats). Cover the boring cases too:
"0 leaks", process-not-found, permission-denied, empty device list.

## What NOT to unit-test
The real `task_for_pid`/`xctrace` round-trip — that needs entitlements + a device and
lives in the **manual integration checklist** (`SPEC.md §6`), run per release, not in CI.

## Definition of test-done for a slice
Failing test existed first · it passes now · edge/error cases covered with fixtures ·
suite is green with zero warnings · `PROGRESS.md` slice row updated.
