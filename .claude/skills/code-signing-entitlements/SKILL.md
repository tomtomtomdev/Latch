---
name: code-signing-entitlements
description: Configure code signing, entitlements, hardened runtime, SIP awareness, notarization, and privilege escalation for Latch — a non-sandboxed macOS developer tool that needs the debugger entitlement to attach to other processes. Use this skill when wiring up task_for_pid permissions, deciding sandbox vs non-sandbox, handling powermetrics root escalation, or preparing the app for distribution. Pushy trigger: consult this whenever an attach/permission error appears, before changing entitlements or signing settings, and ALWAYS verify entitlement keys and notarization steps against current Apple documentation.
---

# Code Signing, Entitlements & Privilege (Latch)

Latch attaches to other processes, so signing/entitlements are load-bearing, not
boilerplate. Get them wrong and `task_for_pid` returns `KERN_FAILURE` with no obvious
cause. **Verify entitlement keys and the notarization flow against current Apple docs**
(`man codesign`, `man notarytool`, developer.apple.com) — details shift.

## The core requirements
- **Sandbox: OFF.** The App Sandbox is incompatible with attaching to arbitrary
  same-UID processes via `task_for_pid`. Latch is a non-sandboxed developer tool.
- **Hardened Runtime: ON**, plus the debugger entitlement:
  - `com.apple.security.cs.debugger` — permits acquiring task ports of other
    (same-UID) processes for inspection.
- Sign with a Developer ID Application certificate for distribution; during dev, an
  Apple Development cert + automatic signing is fine.

Minimal entitlements plist (verify keys before shipping):
```xml
<key>com.apple.security.cs.debugger</key><true/>
<!-- sandbox intentionally absent / disabled -->
```

## What the entitlement does and does NOT grant
- ✅ Acquire task ports of **same-UID** processes you target explicitly.
- ❌ Attach to **SIP-protected / system / other-user / Apple-platform-binary**
  processes. SIP and platform restrictions still apply. These fail by design — handle
  the error, show the user why, treat as out of scope (`SPEC.md §1`).
- The cheap `proc_pid_rusage` / `proc_pidinfo` paths do **not** need this entitlement
  (no task port), which is why the live dashboard leans on them.

## SIP awareness
Do **not** instruct users to disable SIP. Latch must work with SIP enabled for the
in-scope case (the user's own apps). If a target is unreachable due to SIP/platform
protection, that's an expected limitation to communicate, not a bug to "fix" by
weakening the system.

## powermetrics / root escalation
`powermetrics` needs root. Latch must:
- Ask the user explicitly, with a clear reason ("measure per-process energy"), and
  trigger escalation only on that user action — **never silent `sudo`**.
- Prefer an audited escalation path (e.g. an `SMAppService`/privileged helper or an
  authorization prompt) over piping a password. Never handle the password yourself;
  let the system's authorization UI collect it.
- If the user declines, degrade gracefully to the rusage energy estimate and label it.

## Notarization (distribution)
1. Sign with Developer ID + hardened runtime + the entitlements above.
2. `codesign --verify --deep --strict` and `codesign -d --entitlements -` to confirm.
3. Submit with `notarytool submit … --wait`, then `xcrun stapler staple` the app.
4. Verify with `spctl -a -vv` (Gatekeeper assessment).
Confirm the exact commands/flags against current docs before a release.

## Common failure → cause
| Symptom | Likely cause |
|---|---|
| `task_for_pid` → `KERN_FAILURE` | missing debugger entitlement / not hardened / target SIP-protected / different UID |
| Works in Xcode, fails when distributed | entitlement present in debug signing only; not in the release/Developer-ID build |
| Gatekeeper blocks launch | unsigned/un-notarized, or sandbox+debugger conflict |
| powermetrics "must be run as root" | escalation path not wired |

## Rules for Latch
- Keep entitlements minimal — only what a slice needs, justified in the decision log.
- Never commit provisioning profiles or certificates.
- Treat unreachable (SIP/other-UID) targets as a designed limitation with clear UX,
  not an error to engineer around.
