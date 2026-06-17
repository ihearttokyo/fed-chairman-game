## Fed Chairman Game Working Rules

- This repo ships a native macOS game. Treat playability and visual usability as product requirements, not polish.

- Do not declare UI/UX work complete from code-only tests or XCTest/accessibility automation alone. Those tests are regression guards, not proof that the game is usable.

- For any cockpit, panel, chart, dock, settings, briefing, gameplay, or responsive-layout change, run a real GUI validation loop with computer-use when the app can launch in Jared's desktop session:
  - launch the current app build;
  - inspect the first-launch cockpit screenshot;
  - exercise the primary policy decision flow;
  - open Newspaper, Help, and Settings;
  - check at least compact, standard, and large window sizes when layout is touched;
  - inspect screenshots for occlusion, unreadable text, hidden controls, weak hierarchy, confusing affordances, and visual clutter;
  - fix any issue found and repeat the loop.

- Keep XCTest/native UI tests, unit tests, lint, and build checks in the validation suite, but never use them as a replacement for direct visual inspection of the running game.

- If computer-use GUI validation is not run, report it explicitly as `NOT RUN: computer-use GUI validation`, with the reason and the remaining risk.

- Keep generated screenshots, `.xcresult` bundles, build products, and temporary GUI artifacts out of commits unless the user explicitly asks to archive them.
