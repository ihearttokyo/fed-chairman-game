# Loop State

archetype: goal
identity: fed-chairman-playtest-repair-loop
goal_version: fed-chairman-playtest-repair-2026-07-06-v1

primitive_bundle:
  target_shape: finite-criteria
  halt_shape: terminal
  artifact_shape: acceptance-inventory
  convergence_shape: criteria-completion
  cadence_shape: sync

divergences: []
overlays:
  - pressure-weather

consult_tier: tier-2
evaluator_tier: n/a

derivation_read_set:
  - /Users/jared/.codex/skills/loopgen/SKILL.md
  - /Users/jared/.codex/skills/loopgen/templates/composed-prompt.md
  - /Users/jared/.codex/skills/loopgen/archetypes/goal.md
  - /Users/jared/.codex/skills/loopgen/templates/bodies/goal-body.md
  - /Users/jared/.codex/skills/loopgen/primitives/target-shape.md
  - /Users/jared/.codex/skills/loopgen/primitives/halt-shape.md
  - /Users/jared/.codex/skills/loopgen/primitives/artifact-shape.md
  - /Users/jared/.codex/skills/loopgen/primitives/convergence-shape.md
  - /Users/jared/.codex/skills/loopgen/primitives/cadence-shape.md
  - /Users/jared/.codex/skills/loopgen/primitives/consult-capability.md
  - /Users/jared/.codex/skills/loopgen/primitives/frontload-audit.md
  - /Users/jared/.codex/skills/loopgen/primitives/runner-contract.md
  - /Users/jared/.codex/skills/loopgen/primitives/judgment-default.md
  - /Users/jared/.codex/skills/loopgen/primitives/evidence-tier.md
  - /Users/jared/.codex/skills/loopgen/primitives/halt-cause-classifier.md
  - /Users/jared/.codex/skills/loopgen/primitives/queue-as-second-artifact.md
  - /Users/jared/.codex/skills/loopgen/primitives/pressure.md
  - /Users/jared/.codex/skills/loopgen/references/oracle-principles.md
  - /Users/jared/Documents/Fed Chairman Game/AGENTS.md
  - /Users/jared/Documents/Fed Chairman Game/package.json

frontload:
  resolved:
    - motive: close the finite playtest critique inventory.
    - evidence_surface: loop artifacts, npm validation scripts, installed-app provenance, computer-use screenshots.
    - scope_manifest: native macOS game source/docs/tests only; no Web/Tauri/server drift.
    - known_false_green_zones: code-only tests for UI/game feel; stale app screenshots; broad XCUITest loops.
    - forbidden_shortcuts: no criterion deletion, no stale provenance, no broad XCUITest substitution.
    - artifact_locations: loop/PROMPT.md, loop/ACCEPTANCE.md, loop/STATE.md, loop/PRESSURE.md, loop/VERIFY.md.
    - consult_availability: tier-2 available, but bounded and no race-prone worktree spawning by default.
    - final_verify: typecheck, unit tests, lint, install, and one large-window current-build computer-use playtest.
  defaulted:
    - stuck_attempt_n: 3
    - gui_window_policy: one large-window state unless responsive layout is directly touched.
    - ui_suite_policy: skipped unless Jared explicitly requests it.
  open_gaps:
    - save/load/export flows were not exercised in the latest playtest.

artifacts:
  canonical:
    prompt: loop/PROMPT.md
    acceptance: loop/ACCEPTANCE.md
    state: loop/STATE.md
    pressure: loop/PRESSURE.md
    verify: loop/VERIFY.md
  repo_aliases:
    gui_workflow: docs/AGENTIC_GUI_VALIDATION.md
    gui_capture: scripts/agentic-gui-capture.sh
    native_validation: scripts/native-validation.sh

iteration: 3
phase: code-validated
current_artifact: loop/ACCEPTANCE.md
current_criterion: AC-017
last_action: "Implemented and code-validated the AC-017/AC-019 mechanics package: engine-derived four-quarter preview, symmetric expectations anchoring, corrected shock channels, model-versioned saves, honest trace copy, and guarded custom commits."
next_action: "Commit the code-validated package, install that clean commit, and run one large-window multi-quarter computer-use playtest before changing acceptance statuses."
halt_cause: null
halt_scan: []
stuck_counters: {}
final_verify:
  status: partial_package_pass
  transcript: loop/VERIFY.md
oracle_change_notes:
  - "2026-07-10: reopened AC-019 after audit showed clearer credibility copy still describes preview behavior that diverges from the commit engine."
  - "2026-07-10: reopened AC-024 because the package manifest cannot bind a dirty installed artifact to a clean Git commit; current evidence names the limitation explicitly."
  - "2026-07-10: AC-021 conflicts with the newer selection-first design that removed Fast commit; preserve the row pending an explicit authority decision rather than silently restoring or deleting it."

pressure_objects:
  - id: P-001
    source: authored
    scope: validation
    mode: constraint
    strength: high
    satisfied_by: "loop/VERIFY.md records current commit, app path, and executable hash/bundle metadata."
    on_violation: blocks
    expires: "when AC-024 reaches PASS in final-verify."
    status: active
  - id: P-002
    source: authored
    scope: UI validation
    mode: constraint
    strength: high
    satisfied_by: "final verification avoids broad XCUITest unless Jared explicitly requests it."
    on_violation: blocks
    expires: "when AC-025 reaches PASS in final-verify."
    status: active
  - id: P-003
    source: authored
    scope: gameplay mechanics
    mode: burden
    strength: high
    satisfied_by: "engine/source inspection and playtest evidence show economic coherence without arbitrary deterministic penalties."
    on_violation: owes_proof
    expires: "when AC-017 through AC-020 reach PASS."
    status: active
  - id: P-004
    source: authored
    scope: UI surfaces
    mode: preference
    strength: high
    satisfied_by: "screenshots show distinct roles for Desk, Charts, Records, Newspaper, Help, and Settings."
    on_violation: owes_explanation
    expires: "when AC-005, AC-011, AC-013, AC-015, and AC-028 reach PASS."
    status: active
  - id: P-005
    source: mined
    scope: repo workflow
    mode: constraint
    strength: high
    satisfied_by: "root AGENTS.md requires screenshot-first computer-use validation for UI/game work."
    on_violation: blocks
    expires: "if root AGENTS.md changes this rule."
    status: active

pressure_ledger:
  - "2026-07-06: seeded P-001..P-005 during loopgen composition."
  - "2026-07-06: P-001 and P-002 satisfied for this package by current-build provenance and no-XCUITest validation; remain active until full goal final-verify."
  - "2026-07-10: P-004 partially paid by distinct Desk receipt/interpretation/Records roles; P-001 remains open because installed dirty-build provenance is documented but not commit-bound."
pressure_consulted:
  - iteration: 1
    rows:
      P-001: "Requires current-build provenance before accepting screenshots."
      P-002: "Blocks broad XCUITest as a substitute for the visual pass."
      P-003: "Raises proof burden for credibility/economic wording changes."
      P-004: "Prioritizes clarifying existing preview/tape surfaces instead of adding new panels."
      P-005: "Requires screenshot-first GUI validation for the touched UI path."
    criterion: AC-001
    failing_evidence: "Latest playtest found preview label/value pairs stranded across a wide panel and commit/feedback surfaces visually weak."
    hypothesis: "A compact preview card grid plus action-oriented commit row and clearer credibility language will satisfy AC-001 through AC-003 and support AC-019 without adding duplicate surfaces."
    edit_surface: "PolicyDecisionCenter.swift, DecisionFeedback.swift, NativeCoreTests.swift"
    rollback: "Revert the focused files if layout validation worsens readability or tests show semantic regression."
  - iteration: 1
    rows:
      P-001: "Recorded current git commit, installed app path, bundle metadata, executable mtime, and executable sha256."
      P-002: "Skipped broad XCUITest and used code checks plus one large-window computer-use evidence."
      P-003: "Changed credibility copy from rate-cost language to trust/policy-signal language without changing mechanics."
      P-004: "Clarified existing preview/tape surfaces instead of adding another explanation panel."
      P-005: "Ran screenshot-first computer-use validation against the installed app."
    result: "AC-001, AC-002, AC-003, AC-019, AC-024, and AC-025 moved to PASS_PENDING_FINAL."
  - iteration: 2
    rows:
      P-001: "Requires reinstall/provenance before accepting Desk screenshots."
      P-002: "Keeps validation on screenshot-first GUI evidence, not XCUITest."
      P-004: "Selects a clarification/de-duplication move on existing Desk surfaces."
      P-005: "Requires computer-use validation because this is a cockpit layout change."
    criterion: AC-004
    failing_evidence: "Post-commit quarter review is not visible in the default large-window Desk screenshot; the only immediate consequence is the dense Decision Tape receipt."
    hypothesis: "Use the already-visible briefing band as a post-vote quarter review when transmission evidence exists, reserving Decision Tape for receipt and Records for history."
    edit_surface: "FedChairmanGameNativeApp.swift, DashboardHeaderViews.swift, loop artifacts"
    rollback: "Revert the Desk briefing/review layout if post-commit screenshot becomes more crowded or hides primary controls."
  - iteration: 2
    rows:
      P-001: "Recorded HEAD a4e1033, two-file dirty diff fingerprint, installed app path, manifest timestamp, and executable hash without claiming a clean-commit build."
      P-002: "Skipped XCUITest and any responsive matrix; used one 1600x1000 targeted playtest sequence."
      P-004: "Removed the duplicate lower Desk review, reduced Decision Tape to a receipt, and retained detailed review in Records."
      P-005: "Installed twice only because the first visual pass found a concrete panel-height defect; reran the targeted scenario after that code change."
    result: "AC-004, AC-005, and AC-006 moved to PASS_PENDING_FINAL; AC-019 and AC-024 reopened based on stronger-model audit findings."
  - iteration: 3
    rows:
      P-003: "Requires engine-derived rather than hand-estimated preview behavior, grounded shock signs, and symmetric credibility/expectations behavior."
      P-005: "Requires a current-build one-window playtest after the model and preview UI compile and unit gates pass."
    criterion: AC-017
    failing_evidence: "PolicyPreview applies the staged move immediately while QuarterEngine transmits through historical policy gaps; labor-market-heats-up raises unemployment; preview credibility burden differs from the commit rule; custom commit accepts a wider domain than preview."
    hypothesis: "Counterfactual candidate-versus-hold projections through QuarterEngine over its four-quarter lag window will make preview direction, shock lifecycle, and credibility behavior match commits without promising exact forecasts. Splitting labor tightness from financial stress and enforcing the shared +/-150 bps domain will remove arbitrary penalties and bypasses."
    edit_surface: "QuarterEngine.swift, PolicyPreview.swift, GameSessionStore.swift, Policy.swift, PolicyDecisionCenter.swift, FedChairmanGameNativeApp.swift, focused core tests."
    rollback: "Revert the package if hold is not neutral versus its baseline, preview mutates session state, mirrored credibility cases are asymmetric, shock counterfactuals violate documented channels, or the staged custom UI can commit an unpreviewed value."
