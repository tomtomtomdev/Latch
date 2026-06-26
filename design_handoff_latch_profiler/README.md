# Handoff: Latch — macOS App Profiler

## Overview
**Latch** is a macOS developer tool that "latches onto" running iOS and Mac apps and
streams their vitals in real time, automatically detecting six classes of problems:

- Memory leaks
- Zombie objects (use-after-free)
- Performance hitches / dropped frames
- CPU spikes
- High network I/O
- High battery / energy impact

It is aimed at iOS/Mac app developers debugging their own app. The product has two
surfaces: a **main window** (live deep-dive on one attached target) and a **menu-bar
companion** dropdown (glanceable health of all attached targets).

The aesthetic follows native macOS pro-tool conventions (Instruments / Activity Monitor /
Xcode), dark theme.

## About the Design Files
The file in this bundle (`Latch.dc.html`) is a **design reference created in HTML** — an
interactive prototype showing the intended look and live behavior. It is **not production
code to copy directly**. The runtime is a bespoke streaming-template engine inlined as
base64 in the `<head>`; ignore that machinery entirely.

The task is to **recreate this design in the target codebase's environment**. For a real
macOS app this is **SwiftUI/AppKit**; the data plane (attaching to processes, sampling
counters, symbolicating stacks) would come from Instruments/`os_signpost`/`task_info`/
`proc_pidinfo` etc. If this is being built as a web dashboard instead, use the codebase's
existing framework (React/Vue) and charting approach. Treat the HTML purely as a visual +
interaction spec.

## Fidelity
**High-fidelity (hifi).** Final colors, typography, spacing, layout, and interactions are
all specified below and should be reproduced precisely. The only thing that is faked is the
data: all metric streams and detections are synthesized in JS for the prototype — in the
real product they come from live instrumentation.

---

## Layout — Main Window

Overall scene is a fixed **1440 × 940 px** macOS desktop scene:

- **Menu bar** — full width, 26px tall, fixed to top. Translucent (`rgba(20,20,24,.66)` +
  `backdrop-filter: blur(22px)`), 1px bottom border `rgba(255,255,255,.07)`.
- **App window** — positioned `left:24 top:50`, **1392 × 868 px**, `border-radius:12`,
  `overflow:hidden`, background `#17171b`, 1px border `rgba(255,255,255,.09)`, large drop
  shadow `0 44px 110px -22px rgba(0,0,0,.75)`. It is a vertical flex column:
  - **Toolbar** — 54px tall, fixed.
  - **Body** — flex row filling the rest: `Sidebar (222px) | Center (flex) | Right panel (362px)`.

The window is the hero; the menu-bar dropdown overlays it when opened.

### Menu bar (top of scene)
- Left cluster (13px text, `#dadade`, gap 17px): Apple logo (SVG), bold **Latch**, then
  menu titles `Capture · Targets · View · Window · Help` in `#b9b9bd`.
- Right cluster (gap 14px): **Latch status item** (clickable) = the Latch link-icon (SVG,
  stroke `#30D158`) + an amber triangle `▲` (`#FF9F0A`) + bold issue count `4`; hover bg
  `rgba(255,255,255,.1)`, radius 6, padding `2px 9px`. Then a tabular clock
  `Thu 26 Jun  9:41 AM` in `#cfcfd3`.
- Clicking the status item toggles the menu-bar companion dropdown.

### Toolbar (window, 54px)
Background `linear-gradient(#2f2f35, #26262b)`, 1px bottom border `rgba(0,0,0,.45)`, inset
top highlight `0 1px 0 rgba(255,255,255,.05)`. Items, left→right, gap 16px, padding `0 16px`:

1. **Traffic lights** — three 12px circles, gap 8: `#ff5f57`, `#febc2e`, `#28c840`.
2. 1px × 24px divider `rgba(255,255,255,.1)`.
3. **Latch mark** — 18px SVG, two interlocking C's, stroke `#2DD4BF`, width 2.4, round caps.
4. **Title block** (min-width 172): line 1 = target title, 13.5px/600 `#fff`
   (e.g. `Pacer — iOS · iPhone 15 Pro`); line 2 = 11px `#8a8a90` row: 7px green dot
   `#30D158` with pulse animation + text `Latched · 32 ms RTT`.
5. **Live metric chips** (centered, flex:1, gap 8) — five chips. Each chip: padding `5px 9px`,
   bg `rgba(255,255,255,.045)`, 1px border `rgba(255,255,255,.07)`, radius 8; contains an
   8px rounded square in the lane color, a 9.5px/700 `#8a8a90` label, and a tabular
   mono value 12.5px/600 `#ECECEF`. Labels + colors:
   - `CPU` — `#FF9F0A`
   - `MEM` — `#BF5AF2`
   - `NET` — `#64D2FF`
   - `ENERGY` — `#30D158`
   - `FRAME` — `#FF375F`
6. **Range segmented control** — container bg `rgba(0,0,0,.28)`, 1px border, radius 8,
   padding 2. Three buttons `30s · 1m · 5m`, each radius 6, padding `4px 11px`, 11px/600.
   Active: bg `rgba(255,255,255,.16)`, text `#fff`. Inactive: transparent, text `#9b9ba0`.
   Default selected = `1m`.
7. **Pause/Resume button** — padding `6px 13px`, radius 8, 12px/600. Running state: bg
   `rgba(255,255,255,.04)`, 1px border `rgba(255,255,255,.1)`, text `#d0d0d3`, with a 7px
   green dot `#30D158` that blinks. Paused state: bg `rgba(255,159,10,.13)`, border
   `rgba(255,159,10,.45)`, text `#FFB340`, dot solid amber `#FF9F0A`, label `Resume`.
8. **Settings gear** — 32 × 30 icon button, radius 8, 1px border, bg `rgba(255,255,255,.04)`,
   16px gear SVG stroke `#c8c8cd`; hover bg `rgba(255,255,255,.1)`.

### Sidebar (222px)
Background `#1c1c20`, 1px right border `rgba(255,255,255,.07)`, vertical flex.
- **Header** — padding `14px 16px 8px`, space-between: `ATTACHED TARGETS` (10.5px/700,
  letter-spacing 1px, `#6c6c72`) + count `4` (11px `#6c6c72`).
- **Target rows** (scrollable) — each row: flex, gap 10, padding `9px 12px`, radius 9,
  margin `2px 8px`, cursor pointer. Selected: bg `rgba(255,255,255,.08)` + inset left
  accent `inset 2px 0 0 #2DD4BF`. Hover (unselected): bg `rgba(255,255,255,.05)`.
  Row contents:
  - **App icon** — 30px rounded square (radius 8), white 13px/700 initial. iOS targets use
    gradient `linear-gradient(135deg,#2DD4BF,#0A84FF)`; Mac targets `linear-gradient(135deg,#8E8E93,#48484A)`.
  - **Name** (12.5px/600 `#ECECEF`, ellipsis) + **device subtitle** (10.5px `#7e7e85`, ellipsis).
  - **Right stack** — 8px **health dot** (critical `#FF453A`, warning `#FF9F0A`,
    healthy `#30D158`) + **issue badge** (only if issues > 0): 10px/700 white pill,
    min-width 16, radius 7, bg = health color.
- **Footer** — `+ Attach process…` button, full width, padding 8, radius 8, 1px **dashed**
  border `rgba(255,255,255,.15)`, text `#9b9ba0`/600/12px; hover bg `rgba(255,255,255,.04)`,
  text `#cfcfd3`.

Sample target data (4 rows):
| Name | Device | Kind | Health | Issues |
|---|---|---|---|---|
| Pacer | iPhone 15 Pro · iOS 18.2 | iOS | critical | 3 |
| Pacer | Apple Watch S9 · watchOS 11 | iOS | warning | 1 |
| Pacer Sync | This Mac · arm64 | Mac | healthy | 0 |
| Pacer Widget | iPhone 15 Pro | iOS | healthy | 0 |

Selecting a row changes the toolbar title and clears any open detection. (In the prototype
all targets show the same synthesized stream; in production each target streams its own.)

### Center — Live timeline (flex)
Background `#141418`. Two parts:

- **Timeline header** — 42px, bg `#18181c`, 1px bottom border, gap 11, padding `0 16px`:
  8px red dot `#FF453A` blinking, **Live timeline** (13px/600 `#ECECEF`),
  `streaming · 20 Hz` (11px `#7e7e85`), spacer, `frame budget 16.7 ms` (11px `#7e7e85`),
  1px divider, `session` label + tabular mono session clock (e.g. `07:12`, `#cfcfd3`).
- **Lanes area** — flex row: **lane gutter (170px)** + **plot (flex)**.
  - **Lane gutter** — bg `#161619`, 1px right border. Five equal-height rows (flex:1 each),
    each with 1px bottom separator `rgba(255,255,255,.05)`. Row content: a header line
    (9px rounded square lane color + 11px/600 `#c8c8cd` name + right-aligned 9px `#56565c`
    scale hint) and a big tabular **mono current value** (20px/600 `#fff`).
    Lanes (top→bottom): `CPU` (0–100%), `Memory` (live bytes, MB), `Network` (throughput,
    MB/s), `Energy` (impact 0–100), `Frame time` (ms/frame). Colors as in the chips above.
  - **Plot** — a single full-height `<canvas>` filling the area. Drawn each tick:
    - Faint vertical time gridlines (7, `rgba(255,255,255,.045)`).
    - Per lane: a filled area graph normalized to the lane's max, line stroke 1.6px in the
      lane color (with a 7px color glow when the `lineGlow` tweak is on), vertical gradient
      fill from `<color>42` → `<color>06`, and a glowing dot at the latest sample.
    - Lane bands separated by 1px `rgba(255,255,255,.06)`.
    - **Detection markers** — for each detection within the visible window, a vertical line
      across all lanes at its timestamp, colored by severity. Unselected: severity color at
      ~50% alpha, **dashed** (`[3,3]`), 1px, with a small filled triangle flag at top.
      Selected: solid 2px + a faint `rgba` highlight band behind it.
    - **Playhead** — dashed vertical line `rgba(255,255,255,.16)` at the right edge (now).
    - Bottom-left label `−60s` (range-dependent), bottom-right `now`, top-right hint
      `◇ click a marker to inspect`.
  - Clicking a marker (hit-test within ~10px on X) selects that detection and opens the
    detail panel.

### Right panel (362px)
Background `#1a1a1e`, 1px left border. Two mutually-exclusive states.

**A. Detection inbox (default)**
- **Header** — padding `14px 16px 10px`, 1px bottom border, space-between: `DETECTIONS`
  (13px/700, ls .4, `#ECECEF`) + tabular `<n> active` (11px `#7e7e85`); right side two
  filter chips `All` (active: bg `rgba(255,255,255,.08)`, `#cfcfd3`) and `Critical`
  (`#8a8a90`). (Filter chips are visual only in the prototype.)
- **Cards** (scroll, padding `10px 12px`, gap 8) — each detection card: flex, padding
  `10px 11px`, radius 10, 1px border `rgba(255,255,255,.07)` (selected: `<sevColor>66`),
  bg `rgba(255,255,255,.02)` (selected `rgba(255,255,255,.06)`), hover border
  `rgba(255,255,255,.16)`. Contents:
  - 3px-wide full-height **severity bar** (radius 3) in severity color.
  - Title (12.5px/600 `#f2f2f4`, ellipsis) + right **severity label** (10px/700 in sev color).
  - Subtitle (11px `#86868c`, ellipsis).
  - Footer row: **lane chip** (10px/600, padding `2px 7px`, radius 5, text = lane color, bg
    `<laneColor>22`) + relative time `12s ago` (10.5px `#6c6c72`).

**B. Diagnostic detail (when a detection is selected)**
- **Header** — padding `12px 16px`, 1px bottom border: round **back button** (28px, radius
  7, 1px border, chevron-left SVG `#cfcfd3`) + `DIAGNOSTIC DETAIL` (11px/700, ls .5,
  `#7e7e85`) + spacer + **severity badge** (11px/700, padding `3px 9px`, radius 6, text =
  sev color, bg `<sevColor>22`).
- **Body** (scroll, padding 16):
  - Title 16px/700 `#fff`; subtitle 12px `#9b9ba0`.
  - **Meta grid** 2×2 — 1px-gap cells on `rgba(255,255,255,.07)` background, outer 1px
    border, radius 9. Each cell bg `#1f1f24`, padding `9px 11px`: a 9.5px/700 ls-.4
    `#6c6c72` label and a 12px value. Cells: `TARGET`, `DETECTED` (tabular time),
    `<metric label>` (value 12px/600 in lane color), `LANE` (value in lane color).
  - **Description** paragraph, 12.5px/1.55 `#bcbcc2`.
  - **CALL TREE · heaviest stack** section header (10.5px/700, ls .6, `#6c6c72`). Container
    1px border, radius 9, bg `#0f0f12`. Rows: 25px tall, mono 11.5px, 1px bottom separator
    `rgba(255,255,255,.04)`; indent = `depth × 15 + 11` px left padding. Each row: frame
    name (flex, `#d6d6da`, ellipsis) + a 52×5 px **percent bar** track (`rgba(255,255,255,.08)`,
    radius 3) filled to `pct%` in lane color + right-aligned `pct%` (`#9b9ba0`) + right-aligned
    self time (`#6c6c72`).
  - **STACK TRACE** section — 1px border, radius 9, bg `#0f0f12`, padding `10px 12px`,
    horizontal scroll. Each line mono 11px/1.7 `#9ea0a6`, `white-space: pre`.
  - **SUGGESTED FIX** section — one card per fix: flex, padding `9px 11px`, 1px border
    `rgba(48,209,88,.18)`, bg `rgba(48,209,88,.06)`, radius 9; 15px green check SVG `#30D158`
    + fix text 12px/1.5 `#cfd6d0`.
  - **Action buttons** — `Symbolicate` (flex:1, bg `#0A84FF`, white, 12px/600, radius 8,
    hover `#2a95ff`) and `Copy trace` (flex:1, 1px border, bg `rgba(255,255,255,.04)`,
    `#cfcfd3`, hover bg `rgba(255,255,255,.1)`).

---

## Layout — Menu-bar companion dropdown
Shown when the menu-bar Latch status item is clicked. A transparent full-scene backdrop
(z 60) closes it on outside click; the popover stops propagation.

Popover: positioned `top:30 right:14`, **width 346**, radius 14, `overflow:hidden`,
bg `rgba(34,34,40,.82)` + `backdrop-filter: blur(34px) saturate(160%)`, 1px border
`rgba(255,255,255,.12)`, shadow `0 30px 70px -10px rgba(0,0,0,.7)`.

- **Header** — padding `14px 16px`, 1px bottom border: 18px Latch mark (stroke `#2DD4BF`) +
  title block (`Latch` 13.5px/700 `#fff`; `Monitoring 4 targets` 11px `#9b9ba0`) + 8px
  green pulse dot.
- **Target rows** (padding 6) — each: flex, gap 11, padding `9px 10px`, radius 9, hover bg
  `rgba(255,255,255,.07)`. 30px app icon (same gradients/initials as sidebar) + name
  (12.5px/600 `#ECECEF`) + tabular metrics line (10.5px `#9b9ba0`, e.g.
  `CPU 61% · 540 MB · 12 MB/s`) + right status (7px dot + 11px/600 text, both in health
  color: `3 issues` / `1 issue` / `Healthy`).
- **RECENT DETECTIONS** — section label (9.5px/700, ls .6, `#6c6c72`) then up to 3 rows:
  6px severity dot + title (12px `#cfcfd3`, ellipsis) + relative time (10.5px `#6c6c72`).
- **Footer** — padding `10px 12px`, 1px top border, two buttons: `Pause all` / `Resume all`
  (flex:1, 1px border, bg `rgba(255,255,255,.05)`, `#dadade`) and `Open Latch` (flex:1,
  bg `#2DD4BF`, text `#04201b`/700, hover `#39e6cf`).

---

## Interactions & Behavior
- **Live streaming.** Vitals update continuously. In the prototype a timer advances synthetic
  samples ~20–30×/sec and redraws the canvas; readouts (`data-live` nodes) refresh ~6×/sec.
  In production this is driven by the real sampling pipeline. (Implementation note: the
  prototype uses `setInterval`, not `requestAnimationFrame`, so it keeps running even when
  the view/tab is backgrounded — a real app should pause sampling when not frontmost.)
- **Detection lifecycle.** New detections appear periodically: a spike is injected into the
  relevant lane, a marker is placed at the current time, and a card is prepended to the
  inbox feed (kept to ~16). Markers scroll left with the trace and drop off after the window;
  the card remains in the feed.
- **Select a detection** — click a marker on the plot OR a card in the inbox → right panel
  switches to the diagnostic detail for that detection; its marker renders solid/highlighted.
- **Back** — chevron button returns to the inbox.
- **Select a target** — click a sidebar row → updates toolbar title, clears selection.
- **Range** — `30s/1m/5m` rebuilds the buffers/markers for that window length.
- **Pause/Resume** — freezes/resumes the stream (toolbar button and dropdown "Pause all").
- **Menu dropdown** — toggled by the status item; closes on outside click or "Open Latch".
- **Animations:** green "latched" dot pulse (`box-shadow` ripple, 2s loop); red recording dot
  + running pause-dot blink (opacity 1↔.3, ~1.4s); marker flags; canvas line glow.

## State Management
- `selectedTarget` (index) — which attached target the deep-dive shows.
- `selectedIssue` (detection or null) — drives inbox vs. detail panel and marker highlight.
- `paused` (bool) — gates stream advancement.
- `range` (`'30s' | '1m' | '5m'`) — window length; changing it rebuilds buffers + markers.
- `menuOpen` (bool) — menu-bar dropdown visibility.
- `feed` (array of detections, newest first, capped ~16).
- Non-React runtime state (per-lane ring buffers, marker list, sample clock, decaying spike
  amplitudes) — in the prototype these live outside React for perf; in a real app they map to
  your time-series store / instrumentation stream.
- **Data fetching (production):** attach to a process; subscribe to per-metric counters;
  receive detection events with symbolicated call trees + stack traces; request on-demand
  symbolication ("Symbolicate" button).

## Design Tokens

**Backgrounds / surfaces**
- Scene gradient: `radial-gradient(1300px 760px at 78% -12%, #1b2433 0%, #121419 52%, #0c0c0f 100%)`
- Window `#17171b` · Sidebar `#1c1c20` · Center/plot `#141418` · Plot rows `#161619`
- Right panel `#1a1a1e` · Code blocks `#0f0f12` · Meta cell `#1f1f24`
- Timeline header `#18181c`
- Menu bar `rgba(20,20,24,.66)` · Dropdown `rgba(34,34,40,.82)`

**Text**
- Primary `#fff` / `#ECECEF` / `#f2f2f4` · Secondary `#c8c8cd` / `#cfcfd3` / `#dadade`
- Muted `#9b9ba0` / `#8a8a90` / `#86868c` · Faint `#7e7e85` / `#6c6c72` / `#56565c`

**Lane / signal colors**
- CPU `#FF9F0A` · Memory `#BF5AF2` · Network `#64D2FF` · Energy `#30D158` · Frame `#FF375F`

**Severity**
- Critical `#FF453A` · Warning `#FF9F0A` · Info `#0A84FF`

**Health**
- Critical `#FF453A` · Warning `#FF9F0A` · Healthy `#30D158`

**Accent / brand**
- Latch teal `#2DD4BF` (mark, selection accent, primary dropdown button) · System blue `#0A84FF`
- Traffic lights `#ff5f57 / #febc2e / #28c840`

**Borders**
- Hairline `rgba(255,255,255,.06–.09)` · Dark `rgba(0,0,0,.45)` · Dashed (attach) `rgba(255,255,255,.15)`

**Radii** — chips/buttons 8 · cards/sections/icons 9–10 · window 12 · dropdown 14 · small 5–7

**Shadows** — window `0 44px 110px -22px rgba(0,0,0,.75)` · dropdown `0 30px 70px -10px rgba(0,0,0,.7)`

**Type**
- UI: `-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif`
- Numeric / code: `ui-monospace, 'SF Mono', Menlo, monospace`, with `font-variant-numeric: tabular-nums`
- Scale used: 9–10px (labels/badges) · 11–13.5px (body/titles) · 16px (detail title) · 20px (gutter values)

**Tweakable props** (prototype-level; map to settings/feature flags as appropriate)
- `detectionRate`: `Calm | Normal | Stress` — how often detections fire.
- `startPaused`: bool — start with the stream paused.
- `lineGlow`: bool — glow on the graph traces.

## Detection content (sample data used in the prototype)
Each detection has: severity, lane, title, subtitle, metric label + value, description, a
call tree (`depth / name / pct / self-time`), a stack trace (lines), and 1–2 suggested fixes.
The six samples are: **Main-thread hang — 412 ms** (critical, Frame), **Memory leak — retain
cycle** (warning, Memory), **Zombie object messaged** (critical, Frame), **CPU spike — 98%
sustained** (warning, CPU), **High energy impact** (warning, Energy), **High network I/O**
(info, Network). Full copy for each lives in the `pool` array in the design file's logic
class — copy it from there verbatim if you want identical placeholder content.

## Assets
- All icons are **inline SVG** (Apple logo, Latch link-mark, settings gear, back chevron,
  green check). No external image files. App icons are CSS gradient squares with a letter
  initial — replace with real app icons in production.
- No external fonts — system font stack only.
- If implementing in an existing branded codebase, swap Latch's teal/severity palette and
  type for that codebase's design system equivalents.

## Files
- `Latch.dc.html` — the full interactive prototype (main window + menu-bar dropdown). The
  layout/markup lives in the `<x-dc>` template near the top of `<body>`; all behavior and
  the sample data (`lanes`, `pool`, `targetData`, color maps, the streaming/draw loop) live
  in the `class Component extends DCLogic { … }` block lower in the file. The big base64
  `<script>` in the `<head>` is just the prototype runtime — ignore it.
