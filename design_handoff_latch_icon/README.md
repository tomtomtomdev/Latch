# Handoff: Latch — App Icon

## Overview
The application icon for **Latch**, a macOS live app-profiler (attaches to running processes and streams CPU / memory / network / energy / frame-time telemetry). The icon is a dark macOS "squircle" carrying Latch's brand mark: two interlocking hooks (a stylized chain **link / latch**) in a teal→blue gradient, with a small green "live" status dot echoing the app's streaming pulse.

## About the Design Files
The files in this bundle are **design references**, not production assets to ship blindly:
- `latch-icon.svg` — a clean, self-contained vector of the icon at 1024×1024. This is the source of truth for the artwork and is production-usable directly.
- `Latch Icon.dc.html` — the HTML prototype showing the icon at a hero size plus a full dock-size ladder (128 → 16 px). Reference only.
- `preview.png` — rendered reference image.

The task is to produce the platform icon deliverables the target project needs (see **Deliverables** below) from the vector, following the destination toolchain's conventions (Xcode asset catalog, `.icns`, `.ico`, PWA manifest, etc.). If building for macOS, apply the system icon grid/mask rather than baking your own corner radius when the platform provides one.

## Fidelity
**High-fidelity.** Final colors, gradients, geometry, and proportions. Reproduce exactly from `latch-icon.svg`.

## The Icon — construction

Canvas: **1024 × 1024**, all values below in that coordinate space.

### 1. Squircle base
- Rounded-rect / superellipse mask. Simple version: `rx = 228` (≈ 22.3% — the macOS Big Sur ratio). Prefer the platform's superellipse mask if available.
- Fill: linear gradient, top→bottom
  - `0%  #20242C`
  - `48% #15171C`
  - `100% #0E0F12`

### 2. Top sheen (inside the squircle clip)
- Rectangle covering the top ~52% of the icon (`0,0 → 1024,532`).
- Fill: vertical gradient `#FFFFFF @ 0.10 alpha` → `#FFFFFF @ 0 alpha`.

### 3. Halo (inside the squircle clip)
- Circle centered at `512,512`, radius `340`.
- Radial gradient: `#2DD4BF @ 0.34` (center) → `#0A84FF @ 0.16` (42%) → `#0A84FF @ 0` (70%).

### 4. Brand mark — interlocking link
Two rounded hook strokes, no fill:
- `stroke-width: 92`, `stroke-linecap: round`, `stroke-linejoin: round`
- Stroke gradient (`x1 341,y1 256 → x2 683,y2 768`): `#5EEAD4` → `#0A84FF`
- Path A: `M384 298 a170 170 0 0 0 0 340 h106`
- Path B: `M640 726 a170 170 0 0 0 0 -340 h-106`
- (Each arc is a left/right-bulging semicircle of radius 170; together they read as two clasped links, centered ~512,512.)

### 5. Live status dot (drawn on top, not clipped)
- Solid circle: center `700,736`, radius `34`, fill `#30D158`.
- Soft ring: same center, radius `50`, fill `#30D158 @ 0.16 alpha`.
- In the animated HTML mock the dot slowly pulses (opacity 0.5↔0.95, ~2.4s ease-in-out). For a static icon, render it solid; keep the pulse only if a live/animated icon is wanted.

## Small-size guidance
- The dot is **hidden below 48 px** in the mock (it becomes noise). Follow this: omit the dot for 32 px and 16 px variants.
- Shadows and the sheen are per-size in the mock but are cosmetic — the platform usually supplies dock shadowing, so bake only the base + mark + (optional) dot into the raster assets.
- At the smallest sizes the mark should stay centered and legible; do not shrink the stroke weight ratio.

## Design Tokens
- Background gradient stops: `#20242C`, `#15171C`, `#0E0F12`
- Mark gradient: `#5EEAD4` → `#0A84FF`
- Halo: `#2DD4BF`, `#0A84FF`
- Live dot: `#30D158`
- Corner radius ratio: `0.2227` × side
- Mark stroke ratio: `92 / 1024 ≈ 0.09` × side

These match the running Latch app (`Latch.dc.html`): teal `#2DD4BF`, blue `#0A84FF`, green `#30D158`, graphite window chrome.

## Deliverables (typical)
- **macOS**: `AppIcon.appiconset` (16, 32, 128, 256, 512 @1x/@2x) or a generated `.icns`. Provide 1024×1024 master.
- **PWA / web**: `favicon.ico` (16/32/48), 180×180 apple-touch, 192 & 512 PNG for the manifest, plus the SVG.
- Generate all rasters from `latch-icon.svg`.

## Assets
- `latch-icon.svg` — production vector, self-contained (no external fonts/refs).
- Mark geometry is derived from the link glyph used throughout the Latch app UI.

## Files
- `latch-icon.svg`
- `Latch Icon.dc.html` (prototype, reference only)
- `preview.png`
