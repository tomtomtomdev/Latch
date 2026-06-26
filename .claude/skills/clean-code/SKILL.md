---
name: clean-code
description: Apply clean-code principles to Swift/SwiftUI code — naming, function size, single responsibility, dependency direction, and Clean Architecture layer boundaries. Use this skill whenever writing or reviewing code on the Latch project, deciding where a type belongs (Domain/Data/Presentation), naming things, judging whether a function is too big, or asking "is this clean?". Pushy trigger: consult this even for small edits, since boundary and naming drift compounds.
---

# Clean Code (Latch conventions)

Principles distilled for a Swift 6 / SwiftUI / Clean Architecture codebase. This is a
working standard, not a philosophy essay. When in doubt, optimize for the next reader.

## Naming
- Intention-revealing. `physFootprintBytes`, not `mem` or `m`. Units in the name when
  ambiguous (`Bytes`, `PerSec`, `Millis`).
- Types are nouns (`MetricSample`), use cases are verb phrases (`EvaluateThresholds`),
  protocols name a role (`MetricsSource`, `CommandRunner`) — avoid `-Manager`/`-Helper`.
- Booleans read as assertions: `isAttachable`, `requiresRelaunch`.
- One word per concept. Don't mix `fetch`/`get`/`load` for the same operation.

## Functions
- Small. Do one thing at one level of abstraction. If you narrate it with "and", split it.
- Few arguments. 3+ related params → a parameter struct (`DiagnosticOptions`).
- No flag arguments that switch behavior — make two functions or two types.
- No hidden side effects. A `sample()` samples; it does not also mutate global state.
- Command/query separation: a method either does something or answers something.

## Comments
- Prefer code that doesn't need them. Comment the *why*, never the *what*.
- The honest constraints from `SPEC.md §1` are worth a `// NOTE:` where they bite
  (e.g. why zombies relaunch). Delete commented-out code; git remembers.

## Errors
- Typed, meaningful errors at the Data boundary (`enum AttachError`). Don't swallow.
- No force-unwrap / `try!` outside tests. Map system failures to Domain errors with
  enough context to show the user something actionable.

## Clean Architecture boundaries (the load-bearing rule)
- **Domain** imports nothing but the standard library. Entities + use cases + the
  protocols (`MetricsSource`, `DiagnosticRunner`, `TargetDiscovery`) live here.
- **Data** implements those protocols. `Process`, `mach_*`, `proc_*`, C interop, and
  shell strings **never** escape this layer — map them to Domain entities at the edge.
- **Presentation** depends on Domain abstractions only, never on a concrete adapter.
- Dependency rule: source code dependencies point inward. If Domain needs to "know"
  about a backend, you've inverted a dependency wrong — introduce a protocol.

## Smells to act on
Long function · duplicated parsing logic · a `switch` over signal kind repeated in
3 places (→ polymorphism) · a type that reaches across two layers · primitive
obsession (raw `Int` bytes everywhere → a `Bytes` value type) · feature envy (a view
model computing what a use case should).

## Process
Leave each file cleaner than you found it (boy-scout rule), but keep cleanups in
**separate commits** from behavior changes so review and `git bisect` stay sane.
