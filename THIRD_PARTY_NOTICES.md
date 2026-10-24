# Third-party notices

The application embeds the official Godot 4.7.2 runtime. Godot Engine is
MIT-licensed; its bundled third-party components retain their individual licenses.

The in-game **Credits** panel displays the engine license, component copyright
records and license texts obtained from the running engine through
`Engine.get_license_text()`, `Engine.get_copyright_info()` and
`Engine.get_license_info()`. These runtime records are authoritative for the
exported engine build; do not substitute a claim that the app has no dependencies.

The original project and selected soundtrack are attributed to ihearttokyo
personally under the qualified noncommercial freeware terms in `LICENSE`, also
bundled as `game/licenses/THE-CHAIR.txt`. This notice does not relicense Godot
or its components. JRB-1 was generated with Suno; its origin and conversion are
recorded in `ASSET_PROVENANCE.md` and `art/audio/manifest.json`. Suno software
and services are not bundled. FFmpeg is a development-only conversion tool.

Blender is an authoring tool only. Neither Blender nor its Python runtime is
bundled in the game. Apple's signing/export command-line tools and GitHub CI
utilities are development-only. System fonts are supplied by the operating
system rather than redistributed as font files.

Project code and original assets contain no external asset packs, telemetry SDKs,
backend clients or live-data feeds. Inspect licenses and retain notices whenever
an engine build, bundled component or external asset changes before distribution.
