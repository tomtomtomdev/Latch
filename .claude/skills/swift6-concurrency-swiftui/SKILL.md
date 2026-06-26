---
name: swift6-concurrency-swiftui
description: Write correct Swift 6 strict-concurrency and SwiftUI code for Latch — actors, Sendable, @MainActor, structured async sampling loops, @Observable view models, and cancellation. Use this skill when building the polling loop, any async adapter, view-model state, or when a data-race / Sendable / actor-isolation warning appears. Pushy trigger: consult this before writing async code or @Observable types, and treat every strict-concurrency warning as a bug to fix, not silence.
---

# Swift 6 Concurrency & SwiftUI (Latch)

Latch runs continuous sampling loops feeding a reactive UI — exactly where concurrency
bugs hide. Strict concurrency is **on**; zero new warnings is part of Done. Verify
current API shapes via `macos-apple-docs` when unsure.

## Isolation model
- **UI state is `@MainActor`.** `@Observable` view models that publish to SwiftUI run on
  the main actor; mutate their state only there.
- **Sampling/parsing is off-main.** Cheap `proc_*` reads and shell parsing happen on a
  background context; results hop back to the main actor to update published state.
- Use **actors** to protect shared mutable state (e.g. a per-target sample ring buffer
  written by the loop and read by the UI). Don't guard with locks where an actor fits.
- Cross-actor values must be **`Sendable`**. Domain entities (`MetricSample`, `Target`,
  `Finding`) are value types and should be `Sendable` by construction. Don't send
  non-Sendable system handles across actors — map to Domain types at the Data edge.

## The sampling loop pattern
- Drive it with a structured `Task` (or `AsyncStream`) owned by the view model; **store
  the task and cancel it** on detach / view disappearance. Leaking a 1 Hz loop is a
  classic bug.
- Inject the clock so tests advance time instead of sleeping (TDD skill).
- Check `Task.isCancelled` / use `try await` cancellation points each tick.
- Long diagnostic runs (`xctrace`) are their own cancellable child tasks with progress;
  never block the main actor waiting on them.

```swift
@MainActor @Observable final class TargetMonitor {
    private(set) var latest: MetricSample?
    private var loop: Task<Void, Never>?

    func start(_ target: Target, source: any MetricsSource, clock: any Clock) {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let sample = try? await source.sample(target) {
                    self?.latest = sample          // already on main actor
                }
                try? await clock.sleep(for: .seconds(1))
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil }
}
```

## Protocols & Sendability
- Adapter protocols (`MetricsSource`, `DiagnosticRunner`, `TargetDiscovery`) are `async`
  and their inputs/outputs `Sendable`. Implementations that wrap shell calls can be
  actors or `Sendable` structs over a `Sendable` `CommandRunner`.
- Avoid `@unchecked Sendable` — if you reach for it, you probably have a real race.
  Allowed only with a written justification in the decision log.

## SwiftUI specifics
- `@Observable` (Observation) over legacy `ObservableObject` for new view models.
- Keep views dumb: they render `@MainActor` state and send intents; no I/O in `body`.
- Use `.task(id:)` for lifecycle-bound async work so it auto-cancels on disappear /
  id change — pair it with explicit `stop()` for loops you own.

## Warning policy
Every strict-concurrency diagnostic is a design signal: fix the isolation, don't add
`@preconcurrency`/`nonisolated(unsafe)` to silence it. If a third-party/system type
forces a workaround, isolate it behind an adapter and document why.

## Checklist
☐ UI state mutated only on `@MainActor`
☐ shared mutable state behind an actor
☐ cross-actor types are genuinely `Sendable` (no `@unchecked` without justification)
☐ every loop/task is stored and cancelled
☐ clock injected for testability
☐ zero new strict-concurrency warnings
