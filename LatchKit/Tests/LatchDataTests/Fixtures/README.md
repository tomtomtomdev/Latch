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
