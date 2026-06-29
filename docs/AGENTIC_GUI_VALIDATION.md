# Agentic GUI Validation

This repo requires screenshot-first, computer-use validation for UI, UX, and gameplay changes. Native XCTest UI tests are useful regression gates, but they are not an agentic visual QA loop and must not be treated as proof that the game is usable.

## Core Rule

Validate the latest intended build, not whatever app happens to launch. Before any screenshot, click, or visual judgment, prove artifact provenance:

- current git commit under test;
- app path being launched;
- production or local manifest timestamp when available;
- executable SHA-256 or bundle metadata;
- whether the app was built after the relevant source change.

If the app cannot be tied to the commit under test, rebuild/install first. Screenshots from older artifacts may guide debugging, but they are historical evidence and must not be counted as validation.

Do not repeatedly run the same scripted click path. If a validation step opens Newspaper, Help, and Settings in the same order more than once, the next run must have one of these:

- a new code change that directly targets that path;
- a named hypothesis that the run will prove or disprove;
- a different gameplay/window state that changes what is being tested.

Otherwise, stop running tests and inspect the app or code.

Do not run `npm` or XCTest commands in a loop during visual repair. Lint, unit tests, packaging scripts, and UI suites are gates, not discovery tools. For UI/UX defects, the required discovery loop is: build the current app, capture a fresh screenshot from that build, inspect the pixels, patch the visible problem, and rerun only the targeted screenshot scenario that proves the patch. If an automated UI run fails, use its screenshot/artifact or the implicated source code to decide the next patch; do not rerun the same command unless code changed or a new hypothesis is named.

When Jared explicitly asks for native XCUITest coverage, run one large-window suite pass by default. Do not run compact/standard/large responsive matrices, repeated full-suite retries, or targeted rerun loops unless Jared explicitly asks for that exact validation in the current task. If the large-window pass fails because of desktop focus, Codex occlusion, stale geometry assertions, or automation state, stop and report the blocker instead of patching tests and cycling again.

## Validation Ladder

Use the repo-owned ladder instead of raw `xcodebuild test`:

```bash
npm run test:fast
npm run test:gui
npm run test:ui:prepare
npm run test:ui:one -- FedChairmanGameNativeUITests/NativeCockpitUITests/testLaunchStartsWithDockPanelsClosedAndPrimarySurfacesClear
npm run test:ui:final
```

`test:fast` is the inner loop: Swift build plus Swift unit tests. `test:gui` is the screenshot/computer-use evidence path. `test:ui:prepare` runs `build-for-testing` into reusable DerivedData. `test:ui:one` runs exactly one named UI test with `test-without-building` and `-only-testing`. `test:ui:final` is the explicit large-window final gate and is guarded against repeated runs for the same workspace fingerprint.

Do not invoke raw `xcodebuild test` for UI validation. If a second `test:ui:final` is blocked, report the prior result and the guard message. Override only when Jared explicitly asks for another pass.

## Preferred Loop

1. Verify artifact provenance for the app under test. Rebuild/install if the app is stale, ambiguous, or from a different commit.
2. Launch the installed app or current development build.
3. Move or minimize Codex and other windows so they cannot occlude the app under test.
4. Capture a screenshot and app accessibility state with computer-use.
5. Inspect the screenshot directly for layout, hierarchy, readability, occlusion, target size, affordance clarity, and visual quality.
6. Drive the game through meaningful gameplay states:
   - first launch;
   - first decision;
   - several sequential decisions;
   - early, mid, and late quarters;
   - Newspaper open/close after progression;
   - Help and Settings only as workflow coverage;
   - one large-window state by default.
   Check compact, standard, and large responsive sizes only when Jared explicitly asks for responsive validation or the code change directly targets responsive layout.
7. Save screenshots for each meaningful state with stable names.
8. Patch the highest-impact issue found.
9. Repeat only the targeted scenario that proves the patch.
10. Run lint/unit/build checks after the screenshot loop has produced a visually coherent app.
11. Do not run the native XCTest UI suite by default. Use `npm run test:ui:final` only when Jared explicitly requests it, when the change is specifically an accessibility/XCUITest regression, or when a release-grade final gate is truly useful after screenshot validation is already clean.

## Screenshot Evidence

Use `npm run test:gui` only when screenshot evidence from the harness is specifically useful and the desktop/screen-recording state is healthy. Prefer one targeted large-window capture for normal validation; do not use the harness to recreate a responsive screenshot matrix unless Jared asks for responsive coverage.

The capture harness validates that each PNG contains visible pixels. If macOS privacy state or the active desktop returns a black frame, the gate must fail instead of producing false visual evidence. Grant Screen Recording permission to the invoking terminal/app, or use Computer Use directly against the same app bundle and record that screenshot path/evidence in the final report.

Use Computer Use against that same app build for the interactive playability pass: make at least one policy decision, open Newspaper, Help, and Settings, and visually inspect the resulting states.

Use `scripts/agentic-gui-capture.sh` for a single targeted screenshot when the app already exists locally.

Example:

```sh
scripts/agentic-gui-capture.sh --app "/Applications/Fed Chairman Game.app" --size 1180x700 --label q15-newspaper
```

Computer-use screenshots are still preferred when available because they pair pixels with the accessibility tree and allow direct interaction with the running app.

`npm run test:ui` remains available as an alias for the guarded final XCUITest regression gate, but it is deliberately not part of the default validation path and should be skipped for almost all visual/product iteration. If Jared requests it, run one large-window pass unless the current task explicitly asks for responsive matrices or targeted reruns.

## Anti-Patterns

- Looping on `npm test`, `npm run test:ui`, or install/package commands before inspecting the current app screenshot.
- Running raw `xcodebuild test` for UI validation instead of `scripts/native-validation.sh`.
- Rerunning `npm run install:mac` as a substitute for looking at the app.
- Repeating the Newspaper/Help/Settings click path without new code or a new hypothesis.
- Treating XCTest screenshots as sufficient when no model has inspected them.
- Ignoring window occlusion warnings from the GUI runner.
- Declaring success from button existence alone.

## Completion Standard

For UI/UX work, final reports must include:

- the commit and app artifact provenance used for GUI validation;
- the specific gameplay states visually inspected;
- screenshot paths or direct image attachments;
- what problems were found and fixed;
- what was deliberately not rerun and why;
- final code-level and regression checks.
