# Agentic GUI Validation

This repo requires screenshot-first, computer-use validation for UI, UX, and gameplay changes. Native XCTest UI tests are useful regression gates, but they are not an agentic visual QA loop and must not be treated as proof that the game is usable.

## Core Rule

Do not repeatedly run the same scripted click path. If a validation step opens Newspaper, Help, and Settings in the same order more than once, the next run must have one of these:

- a new code change that directly targets that path;
- a named hypothesis that the run will prove or disprove;
- a different gameplay/window state that changes what is being tested.

Otherwise, stop running tests and inspect the app or code.

## Preferred Loop

1. Launch the installed app or current development build.
2. Move or minimize Codex and other windows so they cannot occlude the app under test.
3. Capture a screenshot and app accessibility state with computer-use.
4. Inspect the screenshot directly for layout, hierarchy, readability, occlusion, target size, affordance clarity, and visual quality.
5. Drive the game through meaningful gameplay states:
   - first launch;
   - first decision;
   - several sequential decisions;
   - early, mid, and late quarters;
   - Newspaper open/close after progression;
   - Help and Settings only as workflow coverage;
   - compact, standard, and large windows when responsive layout is touched.
6. Save screenshots for each meaningful state with stable names.
7. Patch the highest-impact issue found.
8. Repeat only the targeted scenario that proves the patch.
9. Run lint/unit/build checks.
10. Run the native XCTest UI suite once as the final regression gate if the desktop is clear enough for reliable interaction.

## Screenshot Evidence

Use `scripts/agentic-gui-capture.sh` when the app exists locally. It creates timestamped screenshots under `/tmp/fed-chairman-agentic-gui/` and prints direct file paths for inspection or final reports.

Example:

```sh
scripts/agentic-gui-capture.sh --app "/Applications/Fed Chairman Game.app" --size 1180x700 --label q15-newspaper
```

Computer-use screenshots are still preferred when available because they pair pixels with the accessibility tree and allow direct interaction with the running app.

## Anti-Patterns

- Rerunning `npm run install:mac` as a substitute for looking at the app.
- Repeating the Newspaper/Help/Settings click path without new code or a new hypothesis.
- Treating XCTest screenshots as sufficient when no model has inspected them.
- Ignoring window occlusion warnings from the GUI runner.
- Declaring success from button existence alone.

## Completion Standard

For UI/UX work, final reports must include:

- the specific gameplay states visually inspected;
- screenshot paths or direct image attachments;
- what problems were found and fixed;
- what was deliberately not rerun and why;
- final code-level and regression checks.
