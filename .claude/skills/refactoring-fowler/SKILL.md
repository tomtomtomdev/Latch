---
name: refactoring-fowler
description: Improve code structure without changing behavior, using Martin Fowler's refactoring catalog, applied to Swift/SwiftUI on the Latch project. Use this skill during the refactor step of TDD, when removing duplication, when a code smell appears (long function, switch repetition, primitive obsession, feature envy), or when reshaping a type to fit Clean Architecture boundaries. Pushy trigger: reach for a named refactoring rather than ad-hoc rewriting whenever tests are green and the code could be cleaner.
---

# Refactoring — Fowler catalog (Latch)

Refactoring = restructuring code **without changing observable behavior**. Precondition:
**green tests**. If you're also changing behavior, that's not a refactoring — do it as a
separate red-green step first, commit, then refactor.

## Discipline
- Take **small steps**; run tests after each. If a step goes red, revert it, don't debug forward.
- Name the refactoring you're doing (it forces intent and aids review).
- **Separate commits** for refactors vs features — `git bisect` and reviewers thank you.
- Refactor to make the *next* change easy; don't gold-plate speculatively (YAGNI).

## Smell → refactoring map (the ones Latch hits most)
| Smell | Refactoring(s) |
|---|---|
| Long function (a parser doing fetch + parse + map) | **Extract Function**, **Split Loop**, **Replace Temp with Query** |
| Duplicated parsing across adapters | **Extract Function** / **Pull Up Method** into a shared parser |
| `switch`/`if` over `SignalKind` repeated in 3+ places | **Replace Conditional with Polymorphism** (per-signal type/strategy) |
| Primitive obsession (raw `Int` bytes, `Double` percent) | **Introduce Parameter Object**, **Replace Primitive with Object** (`Bytes`, `Percent`) |
| Long parameter list on `run(...)` | **Introduce Parameter Object** (`DiagnosticOptions`) |
| Feature envy (view model computing use-case logic) | **Move Function** into the use case |
| Concrete adapter referenced from Presentation | **Extract Interface** / depend on the Domain protocol |
| Flag argument switching behavior | **Replace Parameter with Explicit Methods** / split the type |
| Temporal coupling (must call A before B) | **Combine Functions into Class**, encapsulate the sequence |
| Nested conditionals / early-failure noise | **Replace Nested Conditional with Guard Clauses**, **Decompose Conditional** |

## Common moves, defined briefly
- **Extract Function** — pull a coherent fragment into a named function.
- **Replace Conditional with Polymorphism** — turn a type-switch into dispatch over types
  conforming to a protocol (ideal for the six signals / diagnostic kinds).
- **Introduce Parameter Object** — group params that travel together into a struct.
- **Extract Interface** — name the role a concrete type plays so callers depend on the
  abstraction (this is how Clean Architecture boundaries get enforced).
- **Move Function/Field** — relocate behavior to the type that owns the data it uses.
- **Replace Temp with Query** — swap a local variable for a function so logic is reusable
  and the long function shrinks.

## Latch-specific guidance
- Per-signal and per-diagnostic behavior wants polymorphism, not growing switches.
  When the third `switch SignalKind` appears, stop and extract types.
- Keep refactorings inside one layer; if a refactor wants to cross a Clean Architecture
  boundary, that's a design change — update `SPEC.md` first.
- Value types for measurements (`Bytes`, `Percent`, `BytesPerSecond`) kill a whole class
  of unit-confusion bugs; introduce them early via Replace Primitive with Object.

## When NOT to refactor
Tests red · mid-feature · "while I'm here" scope creep on an unrelated file · no clear
smell (don't refactor for its own sake). Catalog the smell, then act.
