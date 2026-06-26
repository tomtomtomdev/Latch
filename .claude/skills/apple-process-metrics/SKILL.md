---
name: apple-process-metrics
description: Read live per-process metrics on macOS using sanctioned Apple APIs and CLI tools — libproc (proc_pid_rusage, proc_pidinfo, proc_listpids, proc_pidpath), mach task_info, nettop, and powermetrics. Use this skill when building or debugging Latch's live-polling adapters (CPU, memory footprint, threads, disk I/O, network I/O, energy estimate) or enumerating attachable processes. Pushy trigger: consult this before writing any adapter that touches proc_*, mach_*, nettop, or powermetrics, and ALWAYS verify the exact struct fields/flags against the current man pages and headers rather than memory.
---

# Apple Process Metrics (Latch live-poll backends)

How to read another (same-UID) process's vitals cheaply, plus where the cliffs are.
**Verify every struct/flag against the on-machine headers and man pages** — these APIs
gain fields across releases and memory is unreliable. Headers live under the SDK:
`usr/include/libproc.h`, `<sys/proc_info.h>`, `<sys/resource.h>`, `<mach/task_info.h>`.

## Decision: which mechanism for which metric

| Metric | Cheapest path | Needs root? | Needs task port? |
|---|---|---|---|
| CPU time, memory footprint, disk I/O, energy estimate, wakeups | `proc_pid_rusage` | no | no |
| Resident/virtual size, thread count | `proc_pidinfo(PROC_PIDTASKINFO)` | no | no |
| `phys_footprint` (matches Xcode gauge) | `task_info(TASK_VM_INFO)` | no | **yes** (`task_for_pid`) |
| Process list + paths | `proc_listpids` + `proc_pidpath` | no | no |
| Per-process network bytes | `nettop` (CLI) | no | no |
| High-fidelity per-process energy | `powermetrics --samplers tasks` | **yes** | no |

Prefer the no-root, no-task-port column for the live dashboard. Reserve `task_for_pid`
and `powermetrics` for when they're genuinely needed (and gate on permission).

## libproc — the backbone

`proc_pid_rusage(pid_t pid, int flavor, rusage_info_t *buffer)` → fill with the
**highest `RUSAGE_INFO_V*` your deployment target supports** (V6 on recent macOS).
Read fields like (verify names against `<sys/resource.h>`): `ri_phys_footprint`,
`ri_resident_size`, `ri_user_time`, `ri_system_time`, `ri_diskio_bytesread`,
`ri_diskio_byteswritten`, `ri_pkg_idle_wkups`, `ri_interrupt_wkups`, and an energy
field (often `ri_billed_energy` / interval energy — confirm in the header). Times are
in nanoseconds (mach absolute on some fields — confirm and convert).

`proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, sizeof(ti))` → `struct proc_taskinfo`
with `pti_resident_size`, `pti_virtual_size`, `pti_total_user`, `pti_total_system`,
`pti_threadnum`, etc.

Enumerate: `proc_listpids(PROC_ALL_PIDS, 0, buf, size)` then `proc_pidpath(pid, …)`
for the executable path; map pid → display name. Filter to the **current UID** (other
users' processes will fail downstream anyway).

### CPU% derivation
There is no instantaneous CPU% — compute it. Sample cumulative user+system time at
t0 and t1, divide the delta by wall-clock delta, normalize by core count if you want
"% of total" vs "% of one core". Be explicit in the UI which you display.

## mach `task_info` (only when you need the task port)
`task_for_pid(mach_task_self(), pid, &task)` → on success `task_info(task,
TASK_VM_INFO, …)` gives `task_vm_info_data_t.phys_footprint`. **Requires** the
`com.apple.security.cs.debugger` entitlement and same-UID target; SIP-protected procs
return `KERN_FAILURE`/`KERN_PROTECTION_FAILURE`. See `code-signing-entitlements`. Always
handle the failure path — never assume the port.

## nettop (network I/O)
Logging (non-interactive) form, parsed by `NettopMetricsSource`:
```
nettop -P -L 1 -J bytes_in,bytes_out -p <pid>
```
`-P` per-process, `-L 1` one sample then exit, `-J` selects columns (CSV-ish). Parse
cumulative bytes; compute rate from the delta between two samples. Handle "no such
process" and the header row. Confirm flags with `man nettop` (output format shifts).

## powermetrics (high-fidelity energy — root)
```
sudo powermetrics --samplers tasks -n 1 -i <ms>
```
Per-process energy impact + CPU. **Requires root** — Latch must ask for escalation
explicitly and user-initiated (never silent `sudo`); if declined, degrade to the
`rusage` energy estimate and label it as an estimate. Confirm samplers/flags with
`man powermetrics`.

## Implementation rules
- Put each tool behind `CommandRunner`; parse against committed fixtures (TDD skill).
- Map C structs → Domain `MetricSample` at the Data edge; `proc_*`/`mach_*` types do
  not escape the adapter.
- Record provenance: every value remembers which adapter produced it.
- Convert units at the boundary into typed values (`Bytes`, `Percent`).

## Verify-before-trust checklist
☐ struct field names match the SDK header on this machine
☐ time units confirmed and converted
☐ root/entitlement requirement confirmed and gated
☐ failure paths (not-found, denied, SIP) handled
☐ fixture captured from real output with OS version noted
