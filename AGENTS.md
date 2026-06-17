## Fed Chairman Game Working Rules

- This repo ships a native macOS game. Treat playability and visual usability as product requirements, not polish.

- Do not declare UI/UX work complete from code-only tests or XCTest/accessibility automation alone. Those tests are regression guards, not proof that the game is usable.

- For any cockpit, panel, chart, dock, settings, briefing, gameplay, or responsive-layout change, run a real GUI validation loop with computer-use when the app can launch in Jared's desktop session.

- Do not confuse the native XCTest UI suite with an agentic GUI validation loop. XCTest/native UI tests are regression guards and final gates; they are not the primary debug signal for visual quality or gameplay usability. Never repeatedly rerun the same broad suite or the same Newspaper/Help/Settings click pattern hoping it will reveal new information.

- Use [docs/AGENTIC_GUI_VALIDATION.md](docs/AGENTIC_GUI_VALIDATION.md) as the source-of-truth workflow for visual/playability validation. Prefer direct computer-use app state, screenshots, and LLM visual inspection over brittle scripted click loops. Use [scripts/agentic-gui-capture.sh](scripts/agentic-gui-capture.sh) to create timestamped screenshot evidence when a local macOS app build exists.

- Use this agentic GUI loop instead:
  1. Launch the current app build and make sure Codex/other windows are not covering the tested app before any click-based validation.
  2. Capture and inspect the first-launch cockpit screenshot.
  3. Exercise meaningful gameplay paths, not only dock toggles: make several policy decisions, advance to early/mid/late quarters, and verify that chart traces, dots, labels, newspaper panels, and controls remain stable after each state transition.
  4. Open and close Newspaper, Help, and Settings only as part of a broader workflow check; do not repeat that exact click sequence more than once unless a code change directly targets those controls.
  5. Check compact, standard, and large window sizes when layout is touched.
  6. Inspect screenshots for occlusion, unreadable text, hidden controls, weak hierarchy, confusing affordances, stale/reset chart positions, and visual clutter.
  7. Before rerunning any validation path, name the new hypothesis or changed code that makes the rerun useful. If there is no new hypothesis or changed code, stop rerunning and inspect/patch instead.
  8. Fix issues found, then repeat only the targeted scenario that proves the fix. Run the full XCTest/native UI suite once at the end as a regression gate, and skip/rerun it if another app window occludes the tested app.

- Keep XCTest/native UI tests, unit tests, lint, and build checks in the validation suite, but never use them as a replacement for direct visual inspection of the running game.

- If computer-use GUI validation is not run, report it explicitly as `NOT RUN: computer-use GUI validation`, with the reason and the remaining risk.

- Keep generated screenshots, `.xcresult` bundles, build products, and temporary GUI artifacts out of commits unless the user explicitly asks to archive them.
