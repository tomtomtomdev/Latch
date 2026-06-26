---
name: ios-apple-docs
description: Verify iOS framework APIs and on-device profiling constraints against official Apple documentation for Latch — device discovery via devicectl, what can/can't be profiled on a device, and MetricKit as the in-app energy/hang/CPU complement. Use this skill when building the iOS target-discovery and device-routing slice, when reasoning about why an iOS app is or isn't attachable, or when verifying any iOS API. Pushy trigger: consult this before writing any iOS device/profiling code or relying on recalled iOS behavior — on-device profiling has strict, easy-to-get-wrong rules.
---

# iOS Official Docs & On-Device Constraints (verify-then-use)

iOS profiling is far more constrained than macOS. This skill captures the rules Latch
must respect and points to the authoritative sources. **Verify against current docs and
the on-machine tools** (`xcrun devicectl`, `xctrace list devices`) — never assume.

## The hard rules of on-device profiling
- You can profile **only development-signed apps** (your provisioning profile) on a
  **connected, paired, unlocked, trusted** device with a matching developer disk image.
- **App Store apps and arbitrary third-party apps cannot be profiled.** There is no
  sanctioned way to attach to them. Latch must detect ineligibility and say so clearly
  — do not imply otherwise.
- No jailbreak / no unsanctioned attach paths (out of scope, `SPEC.md §1`).
- "Latch onto a running iOS app" therefore means: a dev-signed app you own, on your
  device, routed through `xctrace --device <udid>`.

## Tooling
- **Device discovery / management**: `xcrun devicectl list devices`,
  `xcrun devicectl device info`, `xcrun devicectl device process list` (JSON output —
  parse against a committed fixture). Confirm subcommands with `xcrun devicectl --help`.
- **Profiling**: `xctrace --device <udid>` with templates (Leaks, Allocations, Time
  Profiler, Network, Energy Log). See `instruments-xctrace`.
- Older flows referenced `instruments`/`MobileDevice`; prefer the current
  `devicectl` + `xctrace` path and verify what the installed Xcode supports.

## MetricKit — the in-app complement (for apps you own)
External attach can't read true battery from an arbitrary running iOS app, but if you
own the target app you can integrate **MetricKit** (`MXMetricManager`, `MXMetricPayload`,
`MXDiagnosticPayload`): post-hoc, on-device reports covering CPU, memory, disk, hang
rate, launch time, and **energy**. It is daily/aggregated, not live — offer it as an
optional companion (`PLAN.md` backlog), not as part of live external attach. Verify the
current payload types/availability before integrating.

## Authoritative sources
1. **developer.apple.com/documentation** — framework reference + availability badges,
   and the "Improving your app's performance" / Instruments / MetricKit guides.
2. **On-machine tools** — `xcrun devicectl --help`, `xctrace list devices`,
   `xctrace list templates`: version-exact ground truth for this setup.
3. **Xcode Quick Help** for Swift API signatures and `@available`.

## What to verify every time
☐ The target app is development-signed and the device is eligible (paired/unlocked/trusted).
☐ The `devicectl`/`xctrace` subcommand + flags exist in the installed Xcode.
☐ JSON/output schema matches a captured fixture for this Xcode version.
☐ MetricKit payload fields/availability for the deployment target (if used).
☐ Ineligible-target cases produce a clear, honest user message.

## Anti-patterns
- Implying any iOS app can be profiled.
- Hardcoding `devicectl`/`xctrace` JSON shapes from memory instead of a fixture.
- Treating MetricKit as live/real-time data.
