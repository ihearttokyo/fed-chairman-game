# Game GUI validation

Validate current Godot source or its exact exported artifact. Record the commit,
source hashes, runtime/app path and executable hash or bundle metadata before
screenshots and interaction. An older installed app is historical evidence only.
Use `game/README.md` for the current development and release entry points.

## Background live loop

1. Launch current source through the full official executable path on macOS:
   `/Applications/Godot.app/Contents/MacOS/Godot --path /absolute/repo/game`.
   The short `godot` alias can run the game yet fail Computer Use app binding.
   Give the test instance a private HOME or a new external `--log-file` so its
   native logger cannot replace player crash evidence. Launching a new test
   instance does not authorize replacing the installed app.
2. Before binding or recovering an inactive Computer Use target, verify the exact
   private test PID and launch arguments are still live. A stale macOS app binding
   can automatically open Project Manager with default storage. If the PID is
   absent, do not refresh that binding or send queued inputs. Reconcile the exit;
   continue code/review work rather than treating another window as the test.
   Check the observed window identity before each subsequent mutation group;
   stop the group on an unexpected title or application.
   Bind the exact test app/window through Computer Use. Keep hidden, minimized
   and background windows in that state; never raise, resize, move or activate
   them without the creator's request. If background interaction is blocked, report
   the limitation rather than changing the desktop.
3. Inspect the current-size screenshot for hierarchy, legibility, clipping,
   affordances and access to the main action. For read-only pixels, prefer native
   `screencapture -l <verified-window-id>` rather than full-display capture.
4. Use background Computer Use to stage and adopt meaningful policy choices,
   inspect successive-quarter outcomes, preview/compare without mutation, and
   exercise a relevant bound, cancellation or restoration case. Protect user
   saves: use unsaved test play and never overwrite a stored career for evidence.
5. While the test app is running, read fresh accessibility state after each
   action group before deriving the next element IDs. Selection or layout changes can invalidate earlier IDs.
   Inspect feedback and screenshots; control existence alone is insufficient.
6. Fix the observed defect, then rerun the narrow state that proves the fix.
   A repeat requires changed code, a new hypothesis or a meaningfully different
   gameplay state. Broader current-size/edge checks follow when relevant.
7. Run the affected deterministic tests, correctness and Ponytail review, broader
   game/model checks and release self-check as supporting evidence. Code review
   and passing headless checks cannot substitute for a live usability pass.
8. After quitting a task-owned test app, verify its exact PID has exited with
   `/bin/ps`. End Computer Use on that closed app descriptor: querying it can
   relaunch the app without its private HOME or log arguments. Keep the player
   process untouched. A new test starts again with step 1.

Keep source hashes, saved-career hashes, logs, captures and the observed paths in
one external validation receipt. Black or missing screenshots are failed evidence.
Do not claim visual success from a successful capture command alone. Do not run
retired Swift GUI helpers: they can activate or quit the original installed app.

## Completion

Report source/artifact provenance, meaningful states inspected, visible defects
fixed, screenshot paths, supporting checks and skipped paths. If interaction did
not run, explicitly report `NOT RUN: computer-use GUI validation`, the reason and
remaining risk. Human playtesting, actual assistive-technology use and second-Mac
validation remain separate from model-driven Computer Use.
