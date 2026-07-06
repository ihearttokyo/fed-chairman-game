You are running a terminal goal loop on this repository.

Your job is not to explore the frontier.
Your job is to make a finite acceptance inventory pass without weakening it.

> **Loop provenance - composed by `/loopgen`.**
> Archetype: `goal`  .  Divergences: none.
> Overlays: pressure surface seeded from Jared's playtest feedback, repo GUI-validation rules, and the latest computer-use playtest.
> Consult-capability: `tier-2` (subagent/tool channels are available, but use them only for bounded review or research; do not create extra worktrees unless explicitly authorized).
> Evaluator tier: n/a.
> Frontload - resolved: [`motive`, `evidence surface`, `scope manifest`, `known false-green zones`, `forbidden shortcuts`, `artifact locations`, `consult availability`, `criteria source`, `authority order`, `final-verify`, `dependency topology`]; defaulted: [`stuck-attempt-N=3`, `one large-window GUI state unless code directly targets responsive layout`, `XCUITest skipped unless Jared explicitly requests it`]; open gaps: [`save/load/export were not playtested in the latest run and remain acceptance rows, not assumptions`].
> Primitive sources: `templates/composed-prompt.md`, `archetypes/goal.md`, `templates/bodies/goal-body.md`, `primitives/target-shape.md`, `primitives/halt-shape.md`, `primitives/artifact-shape.md`, `primitives/convergence-shape.md`, `primitives/cadence-shape.md`, `primitives/consult-capability.md`, `primitives/frontload-audit.md`, `primitives/runner-contract.md`, `primitives/judgment-default.md`, `primitives/evidence-tier.md`, `primitives/halt-cause-classifier.md`, `primitives/queue-as-second-artifact.md`, `primitives/pressure.md`, `references/oracle-principles.md`.
> Re-derive (do not hand-edit) when intent, sources, or environment change.

## Motive

Close the playtest critique inventory for the native macOS Fed Chairman Game so the core policy loop is readable, non-duplicative, economically legible, and validated by a fresh installed build plus screenshot-first playtesting.

## Runner Contract

This prompt is runner-agnostic internally. The canonical operator runner is
`/goal`, which re-invokes this prompt iteratively. The prompt assumes only:

1. Iterative re-invocation - you are one iteration.
2. File-persisted state - durable progress lives in named files, not memory.
3. A logical halt signal - emit `stop-and-summarize` when no useful
   iteration remains; the runner maps it.
4. A logical escalate signal - emit `escalate: <reason>` only when
   blocked on something genuinely irreversible or external (paid API
   without budget cap, public-publish, secrets, decisions that cannot
   be rolled back). Reversible judgment is not escalation - see the
   judgment default.

External ceilings (token limits, max-iterations, session length) are
runner concerns, not repository failure. Preserve the worktree and
summarize unresolved work for the next run.

## Judgment default

When the iteration hits a taste-based or inferred judgment call, prefer
the narrow reversible choice + log over pausing:

1. Pick the smallest reversible action consistent with the strongest
   available source.
2. Record an Alignment Review with: problem . context . options
   considered . chosen contract . alignment cost . rollback trigger .
   review question for the human.
3. Continue. Human review happens after the fact.

Escalate (do not proceed) only when the action is irreversible,
externally blocked, or requires authority the loop cannot establish:

- paid APIs without budget caps,
- public-publish or messages-sent actions,
- secrets / credentials,
- product-direction changes whose rollback is unclear,
- source conflict between authoritative-current sources.

**Never call `AskUserQuestion` or any interactive / blocking / approval-prompt
tool, for any reason.** The runner may be unattended, so the call is a deadlock,
not a question. Route a reversible decision to the smallest default above + an
Alignment Review; route a needs-a-human or irreversible one to `escalate` /
`stop-and-summarize` with the question in the summary. Async, never interactive.

## Frontload

Resolved:

- Authority order: Jared's latest critique and playtest feedback, root `AGENTS.md`, current source, current tests/scripts, recent computer-use evidence, then prior docs.
- Evidence surface: `loop/ACCEPTANCE.md`, `loop/STATE.md`, `loop/PRESSURE.md`, `loop/VERIFY.md`, git diff/status, `npm run typecheck`, `npm test`, `npm run lint`, `npm run install:mac`, computer-use screenshots from the current installed build.
- Scope in: native SwiftUI/SpriteKit/game core, docs required to support validation, focused tests.
- Scope out: Web/Tauri/server paths, broad redesign churn, telemetry/backends, generated release artifacts, multi-size XCUITest matrices.
- Known false-green zones: code-only tests for visual quality; accessibility selectors for game feel; screenshots from stale installed apps; broad XCTest loops in an unhealthy desktop state.
- Final-verify: a single repo state where code checks pass, the app is installed from the current commit, and one large-window computer-use playtest covers first launch, preview, commit, post-commit feedback, a secondary mode/panel, and any criterion-specific flow touched.

Defaults:

- Use one canonical worktree.
- Do not run raw `xcodebuild test` for UI. Do not run broad XCUITest unless Jared explicitly asks in the current task.
- Use one large app window for GUI validation unless the edited code directly targets responsive layout.
- If a criterion's best verifier is visual, mark it `PASS_PENDING_FINAL` only after screenshot evidence from the current installed build; mark it `PASS` only after final-verify.
- `STUCK` after 3 failed hypotheses with no new evidence.

Open gaps:

- Save/load/export were not exercised in the latest playtest. Treat them as explicit acceptance rows, not verified behavior.

## Pressure weather

Before selecting work, read `loop/PRESSURE.md` and record in `loop/STATE.md`
which active pressure rows bent the plan. Pressure cannot delete or weaken an
acceptance row; it only changes priority and proof burden.

## Oracle principles

This loop is honest by construction:

1. **Oracle is binary** - pass/fail where possible; never self-assessment.
2. **Oracle independence** - a verifier you author must first fail against
   unmet behavior when that is feasible.
3. **Consumer-side oracle** - if this passes, the player has the working
   experience named by the criterion.
4. **Anti-theater** - `FIXED != CLOSED`. A criterion's own verifier passing
   is `PASS_PENDING_FINAL`, not `PASS`. `PASS` requires final-verify.

## Terminal contract

The run is complete only when every criterion in `loop/ACCEPTANCE.md` for goal
version `fed-chairman-playtest-repair-2026-07-06-v1` reaches `PASS`.

Completion is a specific halt:

1. emit `criteria-met`
2. then emit `stop-and-summarize`
3. label the halt cause `criteria-met`

Do not emit `criteria-met` for partial completion, local green commands,
manual confidence, or "the ugly parts are mostly better."

## Acceptance inventory

`loop/ACCEPTANCE.md` is the frozen critique inventory. Mutable fields are
`status`, `last_verification`, and narrowly scoped Oracle Change Notes only.

Allowed statuses: `OPEN`, `PASS_PENDING_FINAL`, `PASS`, `STUCK`,
`BLOCKED_EXTERNAL`, `QUARANTINED`.

## Channels

- Cheap inner channel: targeted Swift build/unit tests for touched areas, then
  `npm run typecheck`, `npm test`, and `npm run lint` before claiming a package
  is ready.
- Per-criterion verifier: the `verifier` field on each row in
  `loop/ACCEPTANCE.md`.
- Final-verify: `npm run typecheck && npm test && npm run lint`, then
  `npm run install:mac`, then a fresh current-build computer-use playtest in one
  large window. Do not add broad XCUITest to final-verify unless Jared explicitly
  requests it.

## Dependency topology

Dependencies are recorded per row in `loop/ACCEPTANCE.md`. Default to:

1. remove duplication and restore core game-loop clarity,
2. repair policy preview and post-commit feedback,
3. repair panel/mode affordances,
4. repair economic explanation and realism,
5. verify save/export and edge flows.

## Iteration protocol

1. Read `loop/PRESSURE.md`, `loop/ACCEPTANCE.md`, `loop/STATE.md`,
   root `AGENTS.md`, and the current source files relevant to the highest
   priority open row.
2. Confirm the repo is in one canonical worktree and preserve unrelated dirty
   files. Do not create new worktrees or branches unless the user explicitly
   asks.
3. Oracle integrity check before editing: no acceptance row weakened, no
   verifier narrowed to dodge a failure, no UI evidence accepted from a stale
   build.
4. If every criterion is `PASS_PENDING_FINAL` or `PASS`, run final-verify. If it
   proves the whole inventory in one repo state, set all rows to `PASS`, write
   `loop/VERIFY.md`, emit `criteria-met`, then `stop-and-summarize`.
5. Otherwise pick one primary `OPEN` row by dependency, player impact, freshest
   failing evidence, and cheapest meaningful verifier.
6. Before editing, write in `loop/STATE.md`: criterion id, failing evidence,
   hypothesis, edit surface, rollback trigger, and which pressure rows affected
   selection.
7. Implement the smallest coherent product/code change that can satisfy the row.
   Prefer deleting redundancy, clarifying core mechanics, and improving the
   actual play loop over adding new surfaces.
8. Run the cheap inner channel appropriate to the edit. If it fails, fix or
   revert before moving on.
9. For UI/gameplay rows, build/install the current app and perform screenshot-
   first computer-use validation against that artifact. Exercise gameplay, not
   just dock toggles.
10. Mark a row `PASS_PENDING_FINAL` only with criterion-specific evidence. Do
    not mark `PASS` until final-verify passes in the same repo state.
11. Update `loop/STATE.md`, `loop/PRESSURE.md`, and `loop/VERIFY.md` as needed.
    Keep screenshots and temporary GUI artifacts out of commits unless Jared
    explicitly requests archiving them.
12. If validation passes for a coherent package, commit it with explicit staging
    and normal git hygiene. Do not push unless Jared explicitly asks.

## Oracle-drift guard

The loop must not:

- delete a critique because it is inconvenient,
- rewrite a player-facing problem into an implementation-only task,
- accept stale screenshots or stale installed apps as proof,
- rerun broad XCUITest as a substitute for visual inspection,
- add duplicate UI surfaces to hide broken existing ones,
- claim economic realism without source-backed or internally coherent mechanics,
- use a cheat, scripted outcome, or deterministic shock as a proxy for the Fed
  policy loop unless it is explicitly documented as a scenario and grounded in
  the model.

Verifier changes require an Oracle Change Note in `loop/STATE.md`.

## Halt conditions

Halt only when:

- all rows reach `PASS` in final-verify -> `criteria-met` -> `stop-and-summarize`;
- every remaining unpassed row is `STUCK`, `BLOCKED_EXTERNAL`, `QUARANTINED`, or
  wrong-loop-shaped after a full scan -> `partial-deadlock`;
- oracle drift is detected and cannot be repaired without authority ->
  `oracle-drift`;
- a genuine irreversible or external blocker prevents proof -> `genuine-escalate`.

Before any non-terminal halt, scan the full acceptance inventory. A single
blocked row is not enough if another reversible in-scope row can move.

## Artifacts to maintain

- `loop/PROMPT.md` - this re-entrant prompt.
- `loop/ACCEPTANCE.md` - frozen critique inventory and row-level status.
- `loop/STATE.md` - current state, pressure rows, derivation read set, Oracle
  Change Notes, last action, next action.
- `loop/PRESSURE.md` - rendered active pressure field.
- `loop/VERIFY.md` - latest final-verify transcript.

## Repo-specific validation notes

- Use `scripts/agentic-gui-capture.sh` / computer-use evidence for visual proof.
- Do not run `npm run test:ui`, `npm run test:ui:final`, or raw XCUITest unless
  Jared explicitly requests that suite in the current task.
- If a UI row is touched and computer-use GUI validation is unavailable, report
  `NOT RUN: computer-use GUI validation` and keep the row below `PASS`.
- Always record app path, current git commit, and installed executable metadata
  before accepting GUI evidence.
