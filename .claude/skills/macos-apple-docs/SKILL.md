---
name: macos-apple-docs
description: Verify macOS framework APIs against official Apple documentation before using them in Latch, and navigate the right framework for mac app behavior (AppKit/SwiftUI on macOS, system frameworks, on-disk headers, man pages). Use this skill whenever implementing or reviewing any macOS-specific API, when memory of an API signature feels uncertain, or when choosing between framework options on the Mac. Pushy trigger: invoke this before relying on ANY recalled macOS API detail — training data is stale, and the rule on this project is verify-then-use.
---

# macOS Official Docs (verify-then-use)

The operating rule for Latch: **do not trust recalled API details for macOS.** Apple
renames, deprecates, and adds fields constantly. This skill tells you where the
authoritative source is and which framework owns what, so you verify before writing.

## Authoritative sources (in priority order)
1. **On-machine headers & man pages** — fastest and version-exact. SDK headers under
   the active Xcode (`xcrun --show-sdk-path`), and `man <tool>` for CLI tools
   (`leaks`, `nettop`, `powermetrics`, `sample`, `spindump`, `codesign`, `notarytool`).
2. **developer.apple.com/documentation** — framework reference, availability
   annotations (which macOS version introduced/deprecated a symbol), and "Profiling
   your app" / Instruments guides.
3. **Xcode Quick Help / jump-to-definition** — for SwiftUI/AppKit symbols and their
   `@available` annotations.

If web access is available, prefer fetching the current doc page over guessing. If
not, read the on-machine header — it never lies about this machine.

## Framework ownership (for Latch's mac concerns)
- **Process/metrics**: `libproc` (`<libproc.h>`), `<sys/proc_info.h>`,
  `<sys/resource.h>`, Mach `task_info`/`task_for_pid` (`<mach/*.h>`). See
  `apple-process-metrics`.
- **App shell / UI**: SwiftUI for the app, with AppKit interop (`NSWorkspace` for
  running-application info, windowing, menu-bar) where SwiftUI is insufficient.
- **Persistence**: SwiftData (verify model macro/availability for the deployment target).
- **Charts**: Swift Charts for the live timelines.
- **Concurrency**: Swift Concurrency / structured tasks — see `swift6-concurrency-swiftui`.
- **Privilege**: `ServiceManagement` (`SMAppService`) / Authorization Services for the
  powermetrics escalation helper. See `code-signing-entitlements`.

## What to verify every time
☐ Symbol still exists and isn't deprecated for the deployment target (`@available`).
☐ Exact parameter order/types and return semantics (especially C APIs and out-params).
☐ Whether it requires an entitlement, root, or a task port.
☐ Units and ownership/lifetime for anything returning buffers or Mach ports.
☐ For CLI tools: exact flags and output format on THIS OS version (capture a fixture).

## Anti-patterns
- Writing a `proc_*`/`mach_*`/`NS*` call from memory and "fixing it later."
- Assuming a flag exists because it did in an older macOS.
- Treating a `developer.apple.com` page from training as current — check the
  availability badge and version.

When a verification turns up a surprise (renamed field, new requirement), note it in
`PROGRESS.md` so the next slice doesn't relearn it.
