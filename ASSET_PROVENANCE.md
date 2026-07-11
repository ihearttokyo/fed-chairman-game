# Asset Provenance

All visual and audio assets currently used by Classic Monetary Policy Mode are original project assets or native runtime output.

## In-repo assets

- `native/FedChairmanGame/SpriteAtlases/Cockpit.atlas/newspaper-icon.png`, `help-icon.png`, and `cockpit-paper-texture.png`: original cockpit UI art generated for this project with OpenAI image generation on 2026-05-31. Prompts requested abstract newspaper/help command assets and a subtle paper/control-surface texture, while explicitly excluding Federal Reserve seals, government logos, buildings, flags, official emblems, copied interface chrome, text, and letters.
- `native/FedChairmanGame/Assets.xcassets/AppIcon.appiconset/*`, `native/FedChairmanGame/App/AppIconSource.png`, and `native/FedChairmanGame/App/AppIcon.icns`: original native macOS app icon generated for this project with OpenAI image generation on 2026-06-01. The prompt requested a premium command-desk instrument with abstract policy lever, economic traces, rate pips, and newspaper texture, while explicitly excluding Federal Reserve seals, flags, buildings, official emblems, dollar signs, text, and letters.
- Native SwiftUI/SpriteKit chart grids, progress rails, mandate meters, policy buttons, and command-desk panel styling in `native/FedChairmanGame/Sources/FedChairmanNativeApp`: authored from scratch for this project.

## Audio

No audio files are bundled. Current cockpit feedback uses native macOS system sounds through AppKit and respects the in-game sound and reduced-noise settings.

## Prohibited sources

This project must not use Federal Reserve seals, Federal Reserve Bank logos, building photos, screenshots or extracted assets from Chair the Fed, copied source text, copied UI layout, or official-looking government emblems.
