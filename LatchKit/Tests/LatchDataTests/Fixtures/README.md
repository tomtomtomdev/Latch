# nettop fixtures

Recorded real output of the command Latch's `NettopMetricsSource` runs:

```
nettop -P -L 1 -J bytes_in,bytes_out -p <pid>
```

Captured on macOS 15.6 (build 24G84). CSV logging mode always emits raw integer byte
counts (no human-readable suffixes), with a leading header row `,bytes_in,bytes_out,`
and one `<name>.<pid>,<bytes_in>,<bytes_out>,` row per matched process.

- `nettop-traffic.csv` — one process with non-zero cumulative bytes.
- `nettop-no-sockets.csv` — header only: the process has no open sockets, or the pid was
  not found (`nettop` cannot distinguish the two; vitals death-detection is the libproc
  source's job).
- `nettop-multi-row.csv` — multiple matched rows whose byte counts must be summed.

# powermetrics fixtures

Output of the command Latch's `PowermetricsSource` runs to measure per-process energy:

```
powermetrics --samplers tasks --show-process-energy -f plist -n 1 -i 1000
```

⚠️ **Synthesized, NOT captured live.** `powermetrics` requires root (`sudo`), and Latch
never runs a silent `sudo`, so this fixture cannot be captured in the automated flow. It
is hand-authored to match the documented format (`man powermetrics`, macOS 15.6 build
24G84): `-f plist` emits an XML property list with a top-level `tasks` array, one dict per
process keyed by `name`/`pid`, and (with `--show-process-energy`) a per-process
`energy_impact` number. **The exact `energy_impact` key name is an assumption that MUST be
validated against a real privileged run in the manual integration smoke (SPEC §6) before
this slice is trusted in production.** See the slice-5 decision-log entry in `PROGRESS.md`.

- `powermetrics-tasks.plist` — three tasks (`WindowServer`, `apsd` pid 148, and the
  `ALL_TASKS` pid -2 aggregate) each with an `energy_impact`.

# zombie fixtures

Captured **real** `stderr` of a target relaunched with `NSZombieEnabled=YES` — the
command Latch's `ZombieDiagnosticRunner` runs:

```
/usr/bin/env NSZombieEnabled=YES <executable>
```

Captured on macOS 26.2 / Xcode 16 from a throwaway MRC (`-fno-objc-arc`) tool that
over-releases a `LatchLeaky` object then messages it. There is **no `Zombies` Instruments
template/instrument** in current Xcode (verified: `xctrace list templates` /
`list instruments` carry no zombie entry), so zombie detection uses the `NSZombieEnabled`
launch-time env var §1 already mandates — the Obj-C runtime logs the diagnostic to stderr
and the process aborts with `SIGTRAP` (exit 133). `MallocStackLogging` does **not** add a
backtrace to that stderr line, so zombie findings carry no stack (the deeper retain/release
history needs Instruments). See the slice-7 decision-log entry in `PROGRESS.md`.

- `zombie-detected.txt` — a relaunch that messaged a deallocated instance: one
  `*** -[LatchLeaky doWork]: message sent to deallocated instance 0x…` line.
- `zombie-none.txt` — a clean relaunch (proper object lifecycle): normal `NSLog` output,
  no zombie line, exit 0.
- `zombie-launch-failed.txt` — `/usr/bin/env` could not exec the binary (`exit 127`,
  `env: …: No such file or directory`) — the "couldn't relaunch" case.

# sample fixtures

Captured **real** stdout of the command Latch's `SampleDiagnosticRunner` runs:

```
sample <pid> <seconds> <interval-ms>
```

Captured on macOS 26.2 / Xcode 16. `sample` is Latch's verified same-UID hitch/hang
quick-look path: it suspends the target every interval, records all thread call stacks,
and prints a condensed **call tree** with a per-frame sample count (count × interval ≈
time on that frame). It works **without root** (exit 0; a missing process exits 255) —
unlike `spindump`, which "must be run as root when sampling the live system" and is
therefore gated like `powermetrics` (deferred). The deep `xctrace` Time Profiler attach
hits the same debugger-entitlement task-port wall as slice 6's Leaks. The runner finds
the `com.apple.main-thread` block, reconstructs a stack series from its call tree
(each childless leaf → `count` copies of its root→leaf stack), and runs the Domain
`DetectHangs` heuristic. pids sanitized to placeholders. See the slice-8 decision log.

- `sample-hang.txt` — a **wedged** main thread: `sleep` blocked in `__semwait_signal`
  for all 92 samples (× 10 ms = 920 ms), a single non-branching spine → one hang.
- `sample-responsive.txt` — a **busy/responsive** main thread (Python compute): the call
  tree branches into many short-lived leaves. High-count *internal* frames accumulate
  many samples, but no childless **leaf** is wedged ≥ the threshold → **no hang**. Pins
  that the parser flags only wedged leaves, never high-count internal frames.
