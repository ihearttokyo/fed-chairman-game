# Funded-production reference

Opt-in, standard-library Python qualification fixture. Godot remains the game's
only shipping economic implementation. Nothing in `game/` imports this package.

From the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/research/funded_production/tests -v
```

The package reads and verifies the existing model parameters, portfolio reference
and Godot source through repository-relative paths. It needs no private task files,
network, Godot process, Excel session or installed game. It does not write saves.

## What it covers

- One immutable monetary ledger: funded invoices, production, payroll, bank credit,
  signed coupons, principal settlement and physical capital vintages.
- A macro adapter driven by actual paid output and employment, with source-timed
  prices, expectations, credibility and hardship memory.
- Finite NOW/WAIT/NEVER project episodes, explicit no-rollover claims, and a
  conditional waiting option. Operating DCF excludes financing flows; finance
  still constrains feasibility. This is not shareholder NPV or welfare.
- Optional bank payout targets retain only earned profits, reduce owner cash
  distributions and never grant equity/reserves or waive loan covenants. Disabled
  targets preserve baseline transitions; they are not an implemented bank planner.
- Typed checkpoints and exact command replay. Project restrictions survive restore;
  principal paid cannot silently become a refinanced claim.

The golden fixture retains all state fields and non-digest command fields from a
16-quarter committed experiment and its specified quarter-17 resume fork. Class
names were normalized when moving the reference into this package. The fixture
records original file hashes, not proof of original run custody. Package-specific
source digests necessarily differ. This format does not migrate historical Python
checkpoints or native game saves. Digests check consistency, not authenticity.

## Limits before adoption

This is a candidate qualification tool, not a validated replacement simulation.
The source-backed parameters coexist with disclosed authored production and
investment conventions. The public balance-sheet adapter supports only a
stationary same-face Treasury rollover program. Full QE/MBS, currency/RRP and
public-interest accounting are not implemented here. Household allocation is a
fixed structural rule, not an optimal utility solution. Ordinary private default
still refuses the transition rather than modeling an economic successor.

The experiment has **not** established balanced growth, a neutral 240-quarter
career, held-out gameplay improvement, runtime performance, native/workbook
parity or player enjoyment. Flat initial capital vintages are a transition state.
A 64-quarter Python choice forecast is not a qualified game-turn runtime path.
The previously failed gameplay screens remain failed. These tests neither replace
nor waive the game's existing model, save, accessibility, export or release checks.
