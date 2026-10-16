# The Chair — Federal Reserve Policy Lab

A clean-sheet Godot strategy game about monetary policy, built for Apple Silicon
macOS with original Blender assets. Godot is the sole maintained frontend. The
previous Swift implementation is retired to Git history; installed copies and
existing saves remain separate and are not replaced or migrated.

This is a local pre-release candidate, not a market-ready release. Developer ID
signing, Apple notarization, accessibility validation and representative human
playtesting are distinct release gates. The project has no Federal Reserve
affiliation, sponsorship or endorsement.

## Play

Choose one of eight hypothetical economies. At each quarterly meeting, inspect
inflation, employment, expectations and financial conditions; stage a target-rate
midpoint, conditional guidance, asset flow and liquidity request; compare the
applied decision with holding policy; then adopt and inspect the outcome.

Credibility affects guidance and long-term expectations. Public support remembers
hardship and recovers gradually. Policy lags, shocks and history carry through
12-quarter reviews without resets or score-driven dismissal. Careers can continue
for 240 quarters. Exact journal values accompany the charts; city animation is
optional and off by default. Looping music, JRB-1 by Jared Bland,
starts on; the keyboard-accessible Music checkbox stops it and remembers your
choice separately from career saves.

The optional Recurring crises campaign draws from a no-repeat bag of 48
independent concepts, with two conditional bank-finance follow-ups. The seed
determines selection and ordinary 12–20-quarter onset intervals; each authored one-to-four-quarter
profile keeps its fixed magnitudes and timing. Seeded background disturbances
remain unchanged. Dispatches show only the currently observed phase; future
phases and episodes stay hidden from dispatches and previews. Crisis frequency
is fictional game design, not a historical estimate.

Save and Load use the game's separate FedChairmanPolicyLab storage. Loading
validates and replays the career before replacing active play. There is no legacy
save migration. Economic coefficients are disclosed design assumptions; previews
are conditional comparisons, not empirical forecasts or optimal-policy advice.

## Development and validation

Use the globally installed Godot 4.7.2. From the repository root:

```sh
godot --path game
scripts/test-game.sh
scripts/test-model.sh
python3 scripts/tests/test-package-safety.py
validation=$(mktemp -d /tmp/fed-release-check.XXXXXX)
godot --headless --log-file "$validation/engine.log" --path game --quit-after 600 -- --verify-build
```

For macOS Computer Use, launch the full executable path documented in the
[GUI validation workflow](docs/AGENTIC_GUI_VALIDATION.md). Headless checks support
regression confidence; they do not replace visual inspection or gameplay.

Blender is needed only to edit the original city, not to play or run CI. The
[game and model guide](game/README.md) owns equations, units, scenarios, save
semantics, benchmark limitations and packaging instructions.

## Build and release

The [Apple Silicon release workflow](game/README.md#apple-silicon-release) creates
a new ARM64-only Developer ID-signed app and ZIP, retaining validation logs.
The destination must not exist. Signing does not establish Apple notarization
or Gatekeeper acceptance. Never replace an installed app, weaken Gatekeeper or
put credentials, generated bundles, caches or screenshots in Git.

## Sources and ownership

Copyright (c) 2026 Jared Bland, personally, to the extent project rights subsist
and are held by him. [LICENSE](LICENSE) permits personal, noncommercial play
and free sharing of complete, unmodified official binary archives; source
visibility is not an open-source license. Component licenses retain their own
permissions. The full project license and component notices appear in Credits.


- [Current Federal Reserve research](docs/FED_RESEARCH.md)
- [Economic acceptance contract](docs/MODEL_CONTRACT.md)
- [Historical Swift review](docs/REBUILD_REVIEW.md)
- [Original asset provenance](ASSET_PROVENANCE.md)
- [Engine and component notices](THIRD_PARTY_NOTICES.md)
- [Clean-room rules](CLEANROOM.md)

The game runs locally, with no telemetry, accounts, backend or live-data feed.
