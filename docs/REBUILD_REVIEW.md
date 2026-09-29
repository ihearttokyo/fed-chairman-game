# Clean-sheet review

Baseline: `5606875f52bd100981bf21a2e04212de97a5a9c3`, reviewed September 29, 2026.
This is a review of the Swift release, not a claim that a replacement is ready.
The replacement starts with a transparent economic workbook, then a Godot game
and original Blender assets. The existing app and saves remain intact.

## Economic reliability comes first

Winning paths exist, alongside a sharp decline in long-term survival. Easier
loss thresholds would leave the model inconsistencies intact. A benchmark used the unchanged
production core, 500 identical seeds per policy, no access to future shocks, and
up to four terms. Counts below are cumulative survivors, not conditional rates.

| Policy | Term 1 | Term 2 | Term 3 | Term 4 |
| --- | ---: | ---: | ---: | ---: |
| Hold the opening 4% rate | 273 | 19 | 0 | 0 |
| Cut 50 bp once, then hold | 499 | 295 | 188 | 127 |
| Raise 50 bp once, then hold | 79 | 0 | 0 | 0 |
| Balanced feedback | 493 | 326 | 195 | 104 |
| Inflation feedback | 480 | 149 | 24 | 0 |

Balanced feedback targets `1.5 + expected inflation + 1.25*(inflation-2)
- 0.75*(unemployment-5)`, moving at most 50 bp each quarter. Inflation feedback
omits the unemployment term. These are exploratory policies, not optimal
controllers or measurements of human difficulty. The benchmark shows sensitivity
and deteriorating survival; it does not prove that every seed is beatable or
unbeatable. All 227 first-term hold failures exceeded the final unemployment
threshold; none failed the score threshold.

Run the benchmark from the repository root, recording the actual source commit:

```sh
swiftc -O native/FedChairmanGame/Sources/FedChairmanCore/*.swift \
  scripts/audit-legacy-model.swift -o /tmp/fed-chairman-legacy-model-audit
/tmp/fed-chairman-legacy-model-audit "$(git rev-parse HEAD)"
```

### Model findings

| Impact | Root cause and evidence | Replacement requirement |
| --- | --- | --- |
| High | `QuarterEngine.swift` derives GDP growth from the output-gap **level**, then accumulates unemployment from the growth shortfall. In a 96-quarter no-shock test, the gap settles at -1.01% while growth stays near 1.34% against a 2% trend, and unemployment reaches its 15% cap. A constant output gap cannot coexist indefinitely with growth below potential growth. | Derive growth from changes in actual/potential output. Use a consistent labor-gap relationship, with explicit adjustment speed and structural unemployment. |
| High | Credibility support depends on the **sign** of a move and the inflation miss. A 1 bp hike receives the same support as a 50 bp hike even if both leave policy accommodative (`QuarterEngine.swift:118–135`). Static audit. | Reward a credible, effective reaction function and follow-through, not a token directional click. |
| High | `continueNextTerm` discards the lag history and active shocks at Q16. Static audit of the shared transition. | Elections or appointment reviews must not reset the economy's memory. |
| Medium | Supply and energy shocks feed prices but no direct adverse activity channel (`ShockChannels.swift`). Current tests preserve this limitation. | Distinguish demand booms from adverse supply disturbances and credit crises. |
| Medium | Short- and long-horizon expectations are compressed into one number. Public tolerance has no distinct behavioral model. | Separate expectations, policy credibility and public support; expose their feedback, memory and recovery rules. |
| Medium | A fixed 5% unemployment target and automatic score-based reappointment turn invented rules into the apparent institutional mandate. | Label structural employment estimates as uncertain; keep any political game rules explicitly fictional. |
| Medium | Save import checks a digest/version without checking consistency between `current`, `history` and term metadata. Preview and commit can then disagree. Static audit. | Validate the full state at the import boundary; reject inconsistent state without overwriting the current career. |

The 2025 FOMC framework defines a 2% annual PCE inflation objective, but no
fixed numerical employment goal. It calls for a balanced approach when its
objectives conflict, including the different return horizons. Those facts
constrain the new model; they do not supply its numerical coefficients.
[FOMC strategy, amended August 22, 2025](https://www.federalreserve.gov/monetarypolicy/monetary-policy-strategy-tools-and-communications-statement-on-longer-run-goals-monetary-policy-strategy-2025.htm).

## Presentation, persistence and delivery

Two independent read-only code audits covered all core sources and tests, native
presentation, persistence callers, packaging and CI. Parent validation built the
current commit in an isolated, ad-hoc-signed review bundle with separate settings.
The installed game and its career were not modified.

| Finding | Evidence | Required correction |
| --- | --- | --- |
| Debrief says the score missed its threshold even when unemployment caused rejection. | Live run: score 85.1, unemployment 7.62%; `Debrief.swift:239` hardcodes the reason. | Explain the actual failing conditions. |
| Debrief text overlaps the cockpit underneath; chart endpoint labels collide. | Live screenshots at Q16 and Q8. | Opaque, legible layers and collision-aware labels. |
| Career chart remains labeled Q0–Q16 in the second term. | Live Term 2 Q1 screenshot; static `CockpitScene` axis labels. | Derive the axis from the recorded career range. |
| Loading another career can retain a staged action or custom input. | Static native app state/load callers. | Bind staged choices to session identity and quarter. |
| Historical chart inspection is computed but never displayed. | Static `chartInspection`/`ChartInspectionStrip` callers. | One visible, keyboard-accessible historical readout. |
| Activation can reset window position/size; canceled or failed file actions show a success icon. | Static `GameWindowDelegate` and settings status view. | Preserve window state and report the actual result. |
| Main CI is red; packaging is skipped. | GitHub run 29149335565, current baseline. Native UI selectors/hit tests fail. Five recent main runs failed. | Replace stale validation with relevant checks; never call the red baseline a release gate pass. |

The fresh local Swift core suite passed all 45 tests. An earlier build in the
Documents checkout failed because an input was reported modified during build;
its Git content hash still matched HEAD. A fresh checkout outside Documents
passed. That does not establish the filesystem root cause.

One live career lost after an opening 50 bp hike and holds. A second won with
98.5 points after an opening 50 bp cut and holds, then continued into Term 2.
These runs verify paths and visible defects, not balance. The broad XCUITest
suite remained skipped. Existing CI failures were inspected instead.

## What survives the rewrite

Keep deterministic replay, same-model candidate-versus-hold comparisons,
explicit causal traces, a continuous career, portable versioned saves and
accessible controls. Replace the numerical model, score-driven dismissal,
single-lever toolkit and inherited panel layout. Do not carry source defects
forward merely to preserve behavior.

The workbook must be auditable before art or presentation is treated as progress
toward economic reliability. A research-informed reduced-form simulation is
still not a Fed forecasting model. Any coefficient without a documented sample,
identification method and uncertainty remains a design assumption.

Release readiness remains unproven: the Godot replacement, economic acceptance
tests, workbook recalculation, accessibility/playtesting, platform exports and
production signing have not passed yet. Blender and Godot are installed globally;
installation is not release evidence.
