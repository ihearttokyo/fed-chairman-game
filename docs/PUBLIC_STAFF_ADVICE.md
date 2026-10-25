# Public-data staff estimates

The player-facing staff action and bounded routine use one shared rule. It reads
only published, two-decimal inflation, output gap and long inflation expectations.
Its neutral real-rate prior is the scenario's initial design value, disclosed in
How to play. It does not read the evolving neutral rate, short expectations or
future shocks.

Rate = initial neutral prior + long expectations + 1.5 × inflation gap + 0.5 ×
output gap with the default design coefficients. Quotes snap to the admissible
rate grid, including negative rates. This is a fictional feedback estimate, not
an empirically fitted forecast or an optimal policy. It does not directly adjust
for credit spreads, term premiums or weaker negative-rate transmission.

Manual staging changes rate/guidance and selects data dependence; other tools
remain the player's. Routine follow-up retains portfolio switches, resets
one-shot offers and returns control for current events, funding or drift. The
full-information model benchmark remains a diagnostic comparison only.

## Evidence and limits

Independent observer tests change each hidden input while preserving advice;
the diagnostic benchmark changes as a positive control. Invalid public inputs,
overflow, signed half-grid quotes and negative rates have focused tests.
Routine helper and UI tests preserve cancellation, timing, switches and ledgers.
The opt-in full-career test covers all nine shipped scenarios, two development
seeds and 240 quarters with exact independent-actor and save/replay parity.

The opt-in native integration screen compares six 60-quarter paths against the
canonical logged summaries of the frozen public candidate. This establishes
summary parity, not byte-equal trajectories. Inputs/frame timing are simulated
headlessly, forecasts disabled; this is not physical-input UX qualification.
Historical broad-model substitution refuses changed source seams rather than
silently comparing the public rule to itself.

Prior-error experiments expose different inflation/employment costs; near-oracle
results do not establish enough challenge or enjoyment. Removing hidden
information fixes one unfair shortcut, not the entire difficulty problem.
Economic equations and save format are unchanged. Existing saved decisions replay
as before; newly requested staff decisions may differ from prior builds.
