# Asset Provenance

All visual and audio assets currently used by Classic Monetary Policy Mode are original project assets or runtime-generated browser output.

## In-repo assets

- `public/favicon.svg`: hand-authored abstract chart/rate mark created for this project.
- `src-tauri/icons/*`: original macOS app icon generated for this project with OpenAI image generation on 2026-05-31, using a prompt for an abstract monetary-policy command dial. The prompt explicitly prohibited Federal Reserve seals, official government logos, real buildings, flags, text, or letters.
- `src/ui/BrandMark.tsx`: hand-authored SVG React component derived from the same abstract mark.
- CSS chart-paper grids, progress rails, mandate meters, and command-center panel styling in `src/index.css`: authored from scratch for this project.

## Audio

No audio files are bundled. All sound is generated at runtime through Web Audio oscillator/gain nodes in `src/audio`.

## Prohibited sources

This project must not use Federal Reserve seals, Federal Reserve Bank logos, building photos, screenshots or extracted assets from Chair the Fed, copied source text, copied UI layout, or official-looking government emblems.
