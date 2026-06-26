---
name: instruments-xctrace
description: Drive Instruments from the command line via xctrace, plus leaks/sample/spindump, to run Latch's deep on-demand diagnostics (Leaks, Zombies, Time Profiler/hitches, Allocations, Network, Energy) and parse their output. Use this skill when building any DiagnosticRunner adapter, choosing a template, attaching vs launching vs targeting a device, or parsing exported trace data. Pushy trigger: consult this before writing any code that shells out to xctrace, leaks, sample, or spindump, and ALWAYS confirm template/flag names with `xctrace list templates` and `man` on the running machine.
---

# Instruments via xctrace (Latch deep diagnostics)

`xctrace` is the sanctioned CLI front-end to Instruments (`xcrun xctrace`). Latch uses
it for root-causing; the live dashboard stays on cheap APIs. **Confirm everything
against the machine**: `xctrace list templates`, `xctrace list devices`,
`xctrace help`, and `man leaks|sample|spindump`. Template names and export schemas
change between Xcode versions — never hardcode from memory.

## The three target modes
- **Attach** to a running same-UID process: `--attach <pid>`. Good for Leaks,
  Allocations, Time Profiler, Network on something already running.
- **Launch** the target under instrumentation: `--launch -- <path> [args]`.
  **Required** for anything needing launch-time env (Zombies, best-quality
  Allocations/Leaks backtraces via `MallocStackLogging`).
- **Device** (iOS): `--device <udid>`. Target must be development-signed; see
  `ios-apple-docs`.

## Record → export shape
```
xcrun xctrace record --template "<Name>" {--attach <pid> | --launch -- <path> | --device <udid>} \
  --time-limit <Ns> --output <out.trace>
xcrun xctrace export --input <out.trace> --xpath '<toc-xpath>'        # discover schema
xcrun xctrace export --input <out.trace> --xpath '<data-xpath>' > parsed.xml
```
Workflow: first `export` the table-of-contents xpath to learn the schema, then export
the specific data table and parse the XML into Domain `Finding`s. Commit a sanitized
sample export as a fixture and TDD the parser against it.

## Template → signal map (verify exact names with `xctrace list templates`)
| Latch diagnostic | Template (typical) | Mode | Notes |
|---|---|---|---|
| Leaks | `Leaks` | attach or launch | backtraces need `MallocStackLogging` at launch |
| Zombies | `Zombies` | **launch only** | enables `NSZombieEnabled` at launch; cannot attach |
| Hitches / hangs | `Time Profiler` | attach or launch | stacks for stalls; pair with `spindump` for hangs |
| Allocations / growth | `Allocations` | attach or launch | confirm leak-vs-growth |
| Network | `Network` | attach/launch/device | corroborates `nettop` live data |
| Energy | `Energy Log` | launch or device | on-device energy on iOS |

## The Zombies hard rule
`NSZombieEnabled` is an **environment variable applied at process launch**. You cannot
turn it on for an already-running process. Therefore Latch's Zombies feature **must
relaunch** the target (`requiresRelaunch = true`) and the UI must say so plainly. Do
not pretend to "attach for zombies."

## Quick CLI runners (no full trace needed)
- `leaks <pid>` — fast leak snapshot of a running same-UID process. Backtraces are
  meaningful only if the target launched with `MallocStackLogging=1`. Parse the
  "N leaks for M bytes" summary + per-leak blocks; handle the "0 leaks" case.
- `sample <pid> <seconds>` — quick statistical stack sample; cheap way to spot a hot
  function or a wedged main thread.
- `spindump <pid> <seconds>` — heavier; good for diagnosing hangs/beachballs and
  identifying which thread is blocked.

## iOS specifics
Use `--device <udid>` (get it from `xcrun devicectl list devices` or `xctrace list
devices`). Device must be paired, unlocked, trusted, and have a matching developer
disk image; target app must be development-signed. App Store apps cannot be profiled —
surface a clear ineligibility message (see `ios-apple-docs`).

## Implementation rules
- Behind `CommandRunner`; long runs are async with progress + cancellation.
- Never block the main actor on a record that can take seconds–minutes.
- Persist the `.trace` path so the user can open it in Instruments for the full view —
  Latch summarizes, it does not re-implement the trace UI.
- Parse defensively: empty results, partial exports, tool-version differences.

## Verify-before-trust checklist
☐ template name exists in `xctrace list templates`
☐ correct mode (attach/launch/device) for this diagnostic
☐ Zombies uses launch + relaunch UI messaging
☐ export xpath confirmed against a real `.trace`
☐ fixture committed with Xcode/OS version noted
