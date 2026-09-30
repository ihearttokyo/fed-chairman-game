# Fed Chairman Game working rules

Godot in `game/` is the sole maintained frontend and economic implementation.
Preserve `/Applications/Fed Chairman Game.app` and all user saves. The retired
Swift code remains in Git history; no legacy migration or reinstall is implied.

Before model, save, gameplay or packaging changes, read `game/README.md` and
`docs/MODEL_CONTRACT.md`. Keep equations in `game/model/economy.gd`, parameter
units/source classifications in `parameters.json`, and model-version checks
consistent with exports and replay. Disclose invented coefficients and benchmark
limits rather than presenting them as estimated Federal Reserve behavior.

For UI, assets, charts, accessibility or gameplay changes, follow
`docs/AGENTIC_GUI_VALIDATION.md`: verify current-source/build provenance, inspect
pixels and use background Computer Use for meaningful decisions and feedback.
Preserve existing window state. Code-only tests do not prove usability. Report
`NOT RUN: computer-use GUI validation` with its reason and residual risk when
that path cannot run. Keep screenshots and disposable evidence outside Git.

Use the existing game, model, package-safety and release-self-check entry points.
Run the narrow affected regression first; retain deterministic replay and output
replacement safeguards. Build and render heavy jobs serially. Do not turn a
failed check into a pass by weakening its assertion or bypassing platform security.

Every new asset needs provenance in `ASSET_PROVENANCE.md`; bundled code needs
notices in `THIRD_PARTY_NOTICES.md`. Keep source and generated Blender/GLB assets
consistent. Shipping targets ARM64 macOS; universal templates are staging only.
