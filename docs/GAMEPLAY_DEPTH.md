# Gameplay-depth study

The ChatGPT Pro working document, *Fed Chairman Gameplay Depth Experiment*
(17 October 2026), recommends measuring decision value before changing the
simulation. Its source-file SHA-256 is
`589c4be4d8133a1b1188aac80e2037e674deb75d6b38889e7baefd356465c37c`.
It does not recommend shipping delayed observations, persistent borrowers or
standing policy contracts without further evidence. Runtime gameplay AI remains
cancelled.

## Existing result

The private known-seed diagnostic tested eight four-meeting policy plans,
24-quarter consequences and three calculations: conditional, realized and
mechanical continuation. The opening development run covered seeds 0–7 and
checkpoints 0–31: 256 contexts, 6,144 forks and 417,792 attempted and confirmed
native transitions, including replay and repeated baseline reconstruction.

Paired material tradeoffs occurred only at the opening checkpoint, in all eight
seeds. There were no qualifying later opening-period departures or material
preference reversals in this finite menu. This is not a proof of optimal policy,
a held-out result or evidence of enjoyable play. It does not justify making staff
advice deliberately wrong or hiding information to manufacture difficulty.

The later-career stratum, unused-seed confirmation, participant recognition and
sustained enjoyment are unfinished. Later findings cannot rescue the opening
result. A confirmatory executor must reuse each authenticated baseline rather
than repeat the current per-case reconstruction: widening that runner to 624
contexts would exceed the working document's proposed transition allowance.

## Offline choice records

`scripts/gameplay-study.py` implements the document's missing record-ordering
boundary. It does not run the economic diagnostic, drive the game, collect a
human response or decide whether the product passes. It adds no game state,
save migration, dependency or network request.

Use a new absolute directory outside the repository. Preparation binds three
existing files by SHA-256: a development manifest, a participant-safe current
information snapshot, and a private lossless checkpoint. The checkpoint is
hashed, not copied into the participant snapshot. Never use an evaluator-rich
capture containing future shocks as the participant snapshot.

The manifest has exactly these fields:

```json
{
  "study_id": "development-trial-01",
  "scope": "known_development",
  "seed": 1,
  "q": 4,
  "source_ids": {"main.gd": "<actual 64-character SHA-256>"},
  "runtime_sha256": "<actual 64-character SHA-256>"
}
```

Bind all actual engine, actor, renderer and evaluator dependencies in
`source_ids`. The tool records supplied identities; it cannot certify that they
match the native checkpoint, that the snapshot excludes future information, or
that a seed is unused. Confirmatory/held-out manifests are deliberately rejected.

Run with `python3 -B scripts/gameplay-study.py ACTION /absolute/new-study`:

| Action | Inputs and order |
|---|---|
| `prepare` | `--manifest FILE --snapshot FILE --checkpoint FILE` |
| `lock` | `--record FILE`: integer `plan` 0–7; nonempty `current_signal`, `expected_effect`, `reversal_condition` |
| `rate --slot 1` | `--record FILE`: `rater`, Boolean `signal`, `channel`, `reversal`, and nonempty `reason` |
| `rate --slot 2` | Same fields; a distinct identified rater |
| `reveal` | `--record FILE`: the retained evaluator result, read only after choice and both ratings |
| `feedback` | `--record FILE`: integer 1–7 `agency`, `comprehensibility`, `repetition`, `confusion`; nonnegative finite `arithmetic_seconds`; Boolean `continue_playing` |
| `status` | Inspect recorded stages, rater agreement and unverified evidence categories |

Every stage binds all preceding records. New files use exclusive creation and
read-only permissions; retries never replace a choice or a partial record.
Stage files and directory entries are synced before success is reported; a sync
failure is reported without replacing the retained record.
Changed bound manifests, snapshots, checkpoints, earlier chained records or a
revealed result stop the next operation. After an interrupted write, retain that
directory for diagnosis and start a separately identified trial; do not repair
history by overwriting it.

These controls govern this CLI, not a research participant's access to the
filesystem. Timestamps, hashes and different rater names do not prove independent
custody or blinding. A deliberate rewrite of the whole chain is not prevented.
Ratings can disagree without blocking a recorded reveal; the disagreement stays
visible and cannot become a passed recognition gate. `status` never infers
progression, economic correctness, held-out qualification or blinding.

Validate the actual CLI ordering, failure and recovery paths with:

```sh
python3 -B scripts/tests/test-gameplay-study.py
```

The test uses synthetic records only. It is not a substitute for the native
fork/replay checks, the fixed participant trials or sustained playtesting.
