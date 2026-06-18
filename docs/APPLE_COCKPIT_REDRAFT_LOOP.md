# Apple Cockpit Redraft Loop

This branch is rebuilding the native cockpit UI around a content-first, Apple-style desktop game surface. Do not treat this as small polish over the old cockpit.

## Current Branch

- Branch: `codex/native-ui-repair-loop`
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
2. Capture the screenshot matrix below before making visual claims.
3. Inspect screenshots directly. If a screenshot shows overlap, unreadable labels, hidden controls, stale chart state, or weak hierarchy, patch before running broad tests again.
4. Rerun only the targeted scenario that proves the patch. Do not repeat the Newspaper/Help/Settings click path unless the drawer code changed, the gameplay/window state changed, or the run has a named hypothesis.
5. Run lint and unit tests after each coherent patch set. Run the native UI suite only as a final regression gate when the desktop is not blocked by macOS auth/occlusion.

## Screenshot Matrix For Repair Pass

Record provenance once per app artifact before the first screenshot: git commit, app path, app modified timestamp, bundle version/build, executable SHA-256, and whether the artifact was rebuilt from the commit under test.

| Label | Window | State | Acceptance criteria |
| --- | --- | --- | --- |
| `q1-first-launch-1180x700` | 1180x700 | Fresh cockpit, no drawers open | No occlusion; chart, metric cards, dock controls, policy controls, and current rate are visible and readable. |
| `q1-first-launch-1600x1000` | 1600x1000 | Fresh cockpit, no drawers open | Layout expands without floating controls, excessive empty space, or stretched chart artifacts. |
| `q1-newspaper-drawer-1180x700` | 1180x700 | Newspaper opened once from fresh cockpit | Drawer is managed by layout, readable, dismissible, and does not cover required policy controls. |
| `q1-help-drawer-1180x700` | 1180x700 | Help opened once from fresh cockpit | Help content is brief, readable, dismissible, and does not collide with chart or dock controls. |
| `q1-settings-drawer-1180x700` | 1180x700 | Settings opened once from fresh cockpit | Settings controls are readable, targetable, dismissible, and do not hide critical gameplay context. |
| `q6-mixed-policy-chart-1180x700` | 1180x700 | Advance at least five quarters with mixed policy moves | Trend lines, dots, labels, target bands, and decision feedback remain stable after state transitions. |
| `q12-midgame-chart-1360x860` | 1360x860 | Continue into midgame after varied decisions | No stale/reset chart positions; policy area and metrics preserve hierarchy and scanability. |
| `late-game-stress-1600x1000` | 1600x1000 | Late-quarter or stressed economy state when reachable | Dense data remains legible; chart traces and panels do not become cluttered or misleading. |

## Screenshot Evidence

- `/tmp/fed-chairman-redesign/q1-stable-domain.png`
- `/tmp/fed-chairman-redesign/q1-newspaper-slim-drawer.png`
