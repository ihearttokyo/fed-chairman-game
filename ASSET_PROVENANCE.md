# Asset Provenance

All visual and audio assets currently used by Classic Monetary Policy Mode are original project assets or native runtime output.

## In-repo assets

- `native/FedChairmanGame/SpriteAtlases/Cockpit.atlas/newspaper-icon.png`, `help-icon.png`, `settings-icon.png`, and `cockpit-paper-texture.png`: original cockpit UI art generated for this project with OpenAI image generation on 2026-05-31. Prompts requested abstract newspaper/help/settings command assets and a subtle paper/control-surface texture, while explicitly excluding Federal Reserve seals, government logos, buildings, flags, official emblems, copied interface chrome, text, and letters.
- `native/FedChairmanGame/Sources/FedChairmanNativeApp/Resources/newspaper-panel.png` and `native/FedChairmanGame/SpriteAtlases/Cockpit.atlas/newspaper-panel.png`: original generated blank broadsheet art created on 2026-06-01 for the native macOS liquid-glass dock briefing. The prompt requested an antique newspaper panel on a warm mahogany desk with abstract unreadable column texture, subtle chart-like marks, and no readable text, letters, numbers, official marks, Federal Reserve seals, flags, buildings, dollar signs, or copied UI. The source generation is preserved at `/Users/jared/.codex/generated_images/019e7433-0087-7423-8788-f70e5ba64381/ig_0fc2dde8ddfe9ba4016a1c76a61bdc81919d2bbbb75b4feabe.png`.
- `native/FedChairmanGame/Assets.xcassets/AppIcon.appiconset/*`, `native/FedChairmanGame/App/AppIconSource.png`, and `native/FedChairmanGame/App/AppIcon.icns`: original native macOS app icon generated for this project with OpenAI image generation on 2026-06-01. The prompt requested a premium command-desk instrument with abstract policy lever, economic traces, rate pips, and newspaper texture, while explicitly excluding Federal Reserve seals, flags, buildings, official emblems, dollar signs, text, and letters.
- Native SwiftUI/SpriteKit chart grids, progress rails, mandate meters, policy buttons, and command-desk panel styling in `native/FedChairmanGame/Sources/FedChairmanNativeApp`: authored from scratch for this project.

## Audio

No audio files are bundled. Current cockpit feedback uses native macOS system sounds through AppKit and respects the in-game sound and reduced-noise settings.

## Prohibited sources

This project must not use Federal Reserve seals, Federal Reserve Bank logos, building photos, screenshots or extracted assets from Chair the Fed, copied source text, copied UI layout, or official-looking government emblems.
