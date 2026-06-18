# Apple Cockpit Redraft Loop

This branch is rebuilding the native cockpit UI around a content-first, Apple-style desktop game surface. Do not treat this as small polish over the old cockpit.

## Current Branch

- Branch: `codex/apple-liquid-glass-redesign`
- Baseline: `origin/main`
- App under visual test: latest artifact built from this branch only

## Design Goals

- Keep the cockpit readable at 1180x700, 1360x860, and 1600x1000.
- Use glass/material effects as hierarchy and focus, not decoration.
- Keep the dock and panels managed in layout. They must never float over the chart, metric cards, or policy controls.
- Make the chart feel like a native financial dashboard: clean plot area, non-colliding labels, clear target bands, and readable trend history.
- Make Newspaper/Help/Settings brief, useful drawers instead of giant overlays.
- Keep the policy decision workflow one-glance: current rate, move choices, decision feedback, pressure/mandate state.

## Active Defects To Kill

- Fixed in this checkpoint: chart opening dots no longer glue to the y-axis.
- Fixed in this checkpoint: chart x positions now use a stable minimum 16-quarter domain instead of stretching Q1 to the right edge.
- Fixed in this checkpoint: early-history per-series value labels no longer collide with latest dots.
- Fixed in this checkpoint: Newspaper is a slim managed drawer, not a giant broadsheet overlay.
- Fixed in this checkpoint: dock icons are compact controls in the top command area instead of large cards floating over content.
- Still needs follow-up: chart container should be simplified further; it still has a dense, heavy instrument look.
- Still needs follow-up: Help and Settings drawer states need the same screenshot-first pass as Newspaper.
- Still needs follow-up: compact drawer-open mode intentionally prioritizes policy controls and chart over the metrics row; decide whether metrics should remain visible or collapse into a mini strip.

## Validation Loop

1. Build/install the current branch artifact and record commit/hash provenance.
2. Capture first launch at 1180x700 and 1600x1000.
3. Capture Newspaper open, Help open, and Settings open once each.
4. Advance at least five quarters with mixed policy moves and capture the chart.
5. Inspect screenshots directly. If a screenshot shows overlap, unreadable labels, hidden controls, or weak hierarchy, patch before running broad tests again.
6. Run lint and unit tests after each coherent patch set. Run the native UI suite only as a final regression gate when the desktop is not blocked by macOS auth/occlusion.

## Screenshot Evidence

- `/tmp/fed-chairman-redesign/q1-stable-domain.png`
- `/tmp/fed-chairman-redesign/q1-newspaper-slim-drawer.png`
