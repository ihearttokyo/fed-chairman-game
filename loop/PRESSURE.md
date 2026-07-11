# Pressure Weather

Rendered from `loop/STATE.md` `pressure_objects`. Re-render this file whenever
pressure changes; do not treat this file as an independent store.

## Paid Rows

- `P-001` validation constraint, high: GUI evidence must prove current-build
  provenance with commit, app path, and executable metadata. Violation blocks.
- `P-002` UI validation constraint, high: broad XCUITest is not the default proof
  path and must not be run unless Jared explicitly requests it. Violation blocks.
- `P-003` gameplay mechanics burden, high: economic/gameplay changes owe proof
  that they are coherent and not arbitrary deterministic penalties.
- `P-004` UI surfaces preference, high: prefer deleting or clarifying redundant
  surfaces over adding more panels.
- `P-005` repo workflow constraint, high: root `AGENTS.md` requires
  screenshot-first computer-use validation for UI/game work. Violation blocks.

All five rows were paid on 2026-07-11 by the final evidence in
`loop/VERIFY.md`. They remain documented as reopen conditions for future work,
not as active debt in this completed loop.

## Maintenance Rules

- Each iteration records which active pressure rows bent the plan in
  `loop/STATE.md` `pressure_consulted`.
- Pressure may prioritize or increase proof burden, but it may not delete,
  weaken, or suppress an `OPEN` acceptance row.
- A constraint row must be re-tested before it blocks work. If it is not
  re-tested in the current pass, treat it as a burden and record why.
- Retire or mark a row paid only with tier-1/2 evidence named in
  `loop/STATE.md` `pressure_ledger`.
