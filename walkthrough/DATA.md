# Private walkthrough DATA

Eight concise fictional lessons backed by finalized native Career,
PolicyDocket/PolicyCommittee and PricedWorkoutCareer logic. Not a browser game,
new economic engine, empirical forecast or optimal policy. UI is separately
owned. Source: `a91d7dfc8ee2ac04e408285b20203a047711ebd2`.

## Production export and qualification — parent executes once

From the repository root, with `officialGodot` pointing to the same official
Godot 4.7.2 executable already used by the parent:

```sh
: "${officialGodot:?Set to the same official Godot executable as the prior run}"
out=$(mktemp -d /tmp/fed-walkthrough-proof.XXXXXX)
mkdir "$out/home"
HOME="$out/home" "$officialGodot" --headless --log-file "$out/engine.log" \
  --path game --script res://tests/export_walkthrough.gd -- \
  --output "$out/lessons.json" >"$out/console.log" 2>&1
engine_exit=$?
printf 'engine_exit=%s evidence=%s\n' "$engine_exit" "$out"
if [ "$engine_exit" -eq 0 ] && \
   ! grep -Eq '^(SCRIPT ERROR|ERROR):' "$out/console.log" "$out/engine.log"; then
  python3 walkthrough/tests/test-data.py "$out/lessons.json" \
    --native-log "$out/console.log"
else
  cat "$out/console.log" "$out/engine.log"
fi
```

Require zero engine exit, no parse/runtime errors, both
`WALKTHROUGH_ROUNDTRIP_GUARDS_OK` (synthetic comparator self-checks) and
`WALKTHROUGH_EXPORT_OK`, and passing Python qualification. Preserve any prior
distribution data before installing the validated artifact at
`walkthrough/dist/lessons.json`. Recheck the installed **identical** bytes:

```sh
python3 walkthrough/tests/test-data.py walkthrough/dist/lessons.json \
  --native-log "$out/console.log"
```

`--native-log` is REQUIRED for dataset qualification; absent/missing/duplicate
proofs fail. It must be the captured console log for the exact artifact, not an
unrelated engine log. Never manufacture JSON or copy results into tests.

Offline implementation checks only:

```sh
python3 walkthrough/tests/test-data.py --self-test
python3 walkthrough/tests/test-data.py --source-only
```

The source-only mode also reads finalized Git blobs for provenance; it is not
consumer/data qualification. This implementation turn ran self-tests only, no
Git commands or engines. Parent owns native execution and artifact installation.

## Output safeguards and evidence boundary

Exactly `--output /absolute/new/path.json` is required. Defaults, relative or
non-normalized paths, directories, repository destinations and replacements
refuse. The exporter does not create parent directories or new proof files.
Use a fresh private external directory: lexical path checks are not a symlink
sandbox or exclusive-create protection against concurrent writers. Inspect
failed writes before retrying. All careers are new in-memory objects; no user
save is read/written. Logs/screenshots stay outside Git.

Ten native source hashes and the native model digest are pinned. Native policy
validation, payload-byte forecast purity, finite/schema/domain/integral-quarter
checks, textual-key collision checks and raw/normalized document byte-purity
checks remain. Full-precision encoding does not mutate or round native results.
Godot parsing still checks syntax/schema, **not exact numeric recovery**.

## Independent native-float consumer proof

Before serializing lesson data, the exporter visits **every native float** and
records its RFC 6901 JSON-pointer path and IEEE-754 binary64 **little-endian**
8-byte hex. Escapes are `~0` for `~`, `~1` for `/`. It then prints exactly one
single-line JSON record to the existing captured console log:

`WALKTHROUGH_NATIVE_FLOAT64 {"schema_version":1,...}`

Proof fields: `schema_version`, `source_commit`, `model_digest`,
`endianness:"little"`, `float_count`, `floats:{pointer:hex}` and `json_sha256`.
The digest binds exact exported UTF-8 bytes, including the final newline. Proof
bits come from native values **before** serialization, not a parsed or emitted
result; proof construction and encoding are also byte-purity guarded. Hex strings
contain no float-decimal parsing dependency. No new secret/output path is used.

The Python validator independently uses `json.loads` and `struct.pack('<d', ...)`
to check all proved native floats, including policy, initial metrics and all
workout ledger arrays. It rejects missing proof/path/coverage, invalid bits,
nonfinite values, artifact/provenance mismatch and **any nonzero numeric drift**,
reporting path, native/consumer values, bits and ULP difference. Native float
paths serialized as integer numeric tokens are checked too. Parsed float paths
must all be covered. Only explicit +0/−0 numeric equivalence is allowed and
counted; no epsilon or nonzero ULP allowance exists. Qualification reports
`compared`, `signed_zero_equivalences` and `nonzero_differences=0`.

This proves serialization fidelity against an independent Python consumer of
that artifact, not independent economic-model parity. Parent separately reports
that its Node `JSON.parse` diagnostic checked all 3,867 native floats with zero
nonzero differences and 18 negative-zero/positive-zero representations. That is
parent-provided diagnostic evidence, not a browser rerun by this agent or a
hardcoded expected count in the validator.

### Why the old exact Godot-parser gate is nonqualifying

Parent log `/tmp/fed-walkthrough-roundtrip-diag.log` first established 275 native
StringName keys and a spelling difference `quarter:1` versus parsed `quarter:1.0`.
Parent `/tmp/fed-walkthrough-export3.log` subsequently established real recovery
drift inside Godot's parser, e.g. `4.4925945566709276` became
`4.492594556670928`. The exact comparator correctly refused; no tolerance was
introduced. Parent isolated the serializer using native packed float bits and
Node parsing and found no nonzero drift. Accordingly only the **own-parser
exact-value qualification gate** is removed. Its syntax/schema checks and
synthetic exact-comparator unit tests remain. No native JSON-parser roundtrip
byte-parity claim is made. Failed implementation receipts remain preserved.

## Fixed native starts and choices

Q0 is the untouched native opening. Preludes adopt native Hold with default
switches; no custom state, shock edits, future-informed policy or save loading.

| ID | Native scenario | Seed | Meeting | Choices |
| --- | --- | ---: | --- | --- |
| committee | stagflation_bank_run | 417 | Q0 | Native prices/jobs/funding |
| rates | lower_bound_slump | 113 | Q0 | 0% / −2% |
| guidance | unanchored_inflation | 217 | Q0 | Fixed / data-dependent 2.5% announcement |
| portfolio | base | 315 | Q0 | Hold / purchase / sterilize / runoff / no reserve maintenance |
| liquidity | funding_stress | 419 | Q4 after four Holds | No offer / secured offer |
| credibility | unanchored_inflation | 521 | Q0 | Hold / tighter matching guidance |
| recovery | lower_bound_slump | 613 | Q4 after four Holds | Hold / ease |
| workout | stagflation_bank_run | 417 | Q0 native priced-workout recipe | No offer / loan / negative-rate loan |

Committee uses native proposal/policy conversion; workout uses
`bank_workout_opening` and `PricedWorkout.start_episode`, including the
remaining-deposit request index. No economic or accounting formulas are copied.
The original six inspected sources were Career, PolicyDocket, PolicyCommittee,
PricedWorkoutCareer, Economy and scenarios; other dependencies were hash-checked.

## Schema, raw units and information boundary

Top level: `schema_version:1`, `source_commit`, `model_digest`, `lessons`.
Lessons: `id,title,task,scenario,seed,mode:"conditional",source_paths,before,options,takeaway,native_steps`.
Options: `id,label,action,policy,path,notes`; workout adds a native `ledger`.
`before` has inflation, unemployment, output_gap, credibility and support.
`path` has exactly eight native quarterly observations with only these metrics:

| Metric | Native field | Raw units |
| --- | --- | --- |
| quarter | quarter_index | Absolute integer quarter after decision |
| inflation | four_quarter_inflation_pct | Four-quarter percent |
| unemployment | unemployment_rate_pct | Percent |
| output_gap | output_gap_pct | Percent of potential output |
| uncovered_funding | uncovered_funding_pct_initial_gdp | Percent initial annual GDP, not bank losses |
| credibility | credibility | Fraction 0–1 |
| support | public_support | Fictional points 0–100 |
| assets | total_assets_pct_initial_gdp | Percent initial annual GDP, including CB loans |
| loans | outstanding_liquidity_pct_initial_gdp | Percent initial annual GDP, CB loan principal |

Policies retain six raw native control keys and three explicit boolean portfolio
switches. Rates/guidance are percentage points; purchase/loan requests use
**initial**, not current, annual GDP. Offers need not equal settlement.
Workout ledger copies native `bank_states`, `credit_states`, `credit_results`,
`bank_results`, `credit_contexts`; only textual StringName representations are
canonicalized. APR is annual percent with native 90/91/92/92 day scheduling.
Negative APR and collectible-claim assumptions are authored US counterfactuals,
not exact Fed primary-credit governance or GAAP/CECL accounting.

Each native forecast uses today's known shock/request at Q1, then no new shocks
or withdrawals. Existing queues, pressure, inherited restraint and other native
state persist. No future tape/event labels/requests are exported. Q2–Q8 normally
hold the Q1 applied rate, with no fresh assets/loans and persistent switches.
Only guidance uses native `follow_guidance=true` and its published conditional
commitment; this is not adaptive routine follow-up.

Native steps/source paths link committee staging, Help/dispatch, routine
follow-up, interval explanations, objectives and workout debrief. They do not
claim the browser page implements saves, replay, awards or the full game. Eight
forecast quarters do not establish a 60-year Mandate or sustained recovery.
Coefficients/crisis design are fictional. No GUI-usability claim: computer-use
validation was not run here, as explicitly prohibited/delegated to the parent.
