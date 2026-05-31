# Fed Chairman Game

Classic Monetary Policy Mode is a clean-room Fed Chair simulation about one hard question: can you keep the economy close enough to mandate targets to earn another four-year term?

Players make one-click federal funds rate decisions across a real 16-quarter term, read the news shock, watch credibility and macro lags transmit through the economy, then face a reappointment gate. Reappointed chairs continue into another full term with a persistent career timeline.

This project is independent and is not affiliated with, sponsored by, or endorsed by the Board of Governors of the Federal Reserve System or any Federal Reserve Bank.

## What It Includes

- Classic Monetary Policy Mode only: fixed four-year, 16-quarter terms.
- One-click policy moves plus custom basis-point moves.
- Deterministic seeded shocks, credibility, policy lags, scorecards, and reappointment debriefs.
- Full-career chart/table history that appends across terms instead of resetting.
- Portable `.fedchair-save.json` saves with tamper-evident SHA-256 digests.
- CSV, JSON, and Markdown exports for the full career timeline.
- Accessible light/dark cockpit theme, reduced motion support, keyboard shortcuts, and Web Audio that fails closed.
- Web app, local click-to-run launcher, standalone local Mac bundle, and Tauri/Rust desktop DMG packaging.

## Gameplay Loop

1. Read the quarterly briefing and any shock report.
2. Inspect the mandate dashboard: inflation, unemployment, fed funds, credibility, and policy path.
3. Commit one policy move atomically.
4. Review the model trace and three-month transmission readout.
5. Complete 16 quarters, face reappointment, then continue or retire when eligible.

## Quick Start

```bash
npm install
npm run dev
```

Open `http://127.0.0.1:5173/`.

## Click-To-Run Options

### Local macOS command launcher

Double-click:

```text
Fed Chairman Game.command
```

Or run:

```bash
npm run launch
```

This builds when needed, starts a local production preview server, and opens the game in your browser.

### Native macOS desktop DMG

```bash
npm run package:desktop:mac
open "release/Fed Chairman Game.dmg"
```

The desktop shell uses Tauri/Rust to load the same React build inside a native macOS window. The package command builds the app, stages a clean copy outside the FileProvider-backed project folder, strips extended attributes, ad-hoc signs it, creates `release/Fed Chairman Game.dmg`, mounts it read-only, verifies the mounted app signature, and performs a launch smoke.

Current limitation: this is ad-hoc signed, not Developer ID signed or notarized.

### Self-contained local server bundle

```bash
npm run package:mac:standalone
npm run verify:mac:standalone
```

This creates `release/Fed Chairman Game Standalone.zip`, which contains a local-server `.app` with built assets plus embedded Node runtime dependencies. Use the Tauri DMG for the preferred desktop path.

## Verification

```bash
npm run typecheck
npm run lint
npm test -- --run --maxWorkers=1
npm run build
npm run perf:budget
npm run e2e
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo check --manifest-path src-tauri/Cargo.toml
npm run desktop:verify
```

Fresh machines can install Playwright Chromium with:

```bash
npm run playwright:install
```

`npm run e2e` also repairs a missing Playwright Chromium cache before running.

## Tech Stack

- React 19, TypeScript, Vite
- Zustand for local state
- Recharts for the mandate dashboard
- Zod for save/session validation
- Vitest and Playwright for test coverage
- Tauri 2 and Rust for native desktop packaging

## Project Map

```text
src/
  engine/       deterministic macro model, policy decisions, score engine
  features/     gameplay panels: briefing, policy, history, results, export
  state/        session store, save-file envelope, exporters, schema validation
  ui/           shared visual components and theme support
src-tauri/      Tauri/Rust desktop shell
scripts/        launch, packaging, verification, and performance-budget scripts
e2e/            Playwright gameplay coverage
```

## Release Artifacts

Generated release artifacts are intentionally ignored by git:

- `release/Fed Chairman Game.dmg`
- `release/Fed Chairman Game Standalone.zip`
- `dist/`
- `src-tauri/target/`

Build them locally or attach them to a private GitHub release when needed.

## Clean-Room Discipline

The game uses original UI, copy, model code, and assets only. It does not include Federal Reserve seals, Federal Reserve building photos, screenshots from other products, copied source text, external audio packs, backend services, telemetry, accounts, or live economic data.

Supporting docs:

- `ASSET_PROVENANCE.md`
- `CLEANROOM.md`
- `THIRD_PARTY_NOTICES.md`
