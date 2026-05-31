# Fed Chairman Game

Fed Chairman Game is a clean-room macOS desktop simulation about the pressure of running monetary policy across real four-year Fed Chair terms.

Players make one policy decision per quarter, read the briefing, watch credibility and macro lags transmit through the economy, then face a reappointment decision after 16 quarters. Reappointed chairs continue into another full term with one continuous career history.

This project is independent and is not affiliated with, sponsored by, or endorsed by the Board of Governors of the Federal Reserve System or any Federal Reserve Bank.

## Beta Scope

- Native macOS desktop app built with Tauri 2 and Rust.
- Classic Monetary Policy Mode only: fixed four-year, 16-quarter terms.
- One-click rate decisions plus validated custom basis-point moves.
- Deterministic seeded shocks, credibility, policy lags, scorecards, and reappointment debriefs.
- Full-career chart and table history that append across terms.
- Portable `.fedchair-save.json` saves with tamper-evident SHA-256 digests.
- CSV, JSON, and Markdown exports for the full career timeline.
- Accessible light/dark cockpit theme, reduced motion support, keyboard shortcuts, and fail-closed Web Audio.

The release direction is intentionally narrow: one macOS desktop application. There are no browser-launcher, website, or standalone local-server product paths.

## Gameplay Loop

1. Read the quarterly briefing and any shock report.
2. Inspect inflation, unemployment, fed funds, credibility, and the policy path.
3. Commit exactly one policy move for the quarter.
4. Review the model trace and three-month transmission readout.
5. Complete 16 quarters, face reappointment, then continue or retire when eligible.

## Development

```bash
npm install
npm run dev
```

`npm run dev` opens the desktop app in Tauri. Development tooling may start a local UI process, but the product direction and shipped app are desktop-only.

## Build

```bash
npm run build
```

This builds the production macOS app bundle through Tauri.

For a local beta candidate:

```bash
npm run package:mac
```

The packaging command stages a clean app bundle outside the FileProvider-backed project folder, strips extended attributes, ad-hoc signs it, creates a local macOS disk image, mounts it read-only, verifies the mounted app signature, and performs a launch smoke.

Current limitation: beta builds are ad-hoc signed, not Developer ID signed or notarized.

## Verification

```bash
npm run typecheck
npm run lint
npm test -- --run --maxWorkers=1
npm run build:frontend
npm run perf:budget
npm run e2e
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo check --manifest-path src-tauri/Cargo.toml
npm run build
npm run verify:desktop
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
scripts/        desktop packaging, desktop verification, and performance-budget scripts
e2e/            Playwright gameplay coverage
```

## Release Artifacts

Generated artifacts are intentionally ignored by git:

- `release/`
- `dist/`
- `src-tauri/target/`

Build artifacts locally when cutting a private beta release. Do not commit generated app bundles, disk images, or build output.

## Clean-Room Discipline

The game uses original UI, copy, model code, and assets only. It does not include Federal Reserve seals, Federal Reserve building photos, screenshots from other products, copied source text, external audio packs, backend services, telemetry, accounts, or live economic data.

Supporting docs:

- `ASSET_PROVENANCE.md`
- `CLEANROOM.md`
- `THIRD_PARTY_NOTICES.md`
