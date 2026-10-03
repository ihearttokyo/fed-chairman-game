import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const ids = ['base', 'demand_boom', 'supply_shock', 'funding_stress', 'unanchored_inflation', 'lower_bound_slump', 'mixed_crises'];
const cases = await Promise.all(ids.map(async id => JSON.parse(await fs.readFile(new URL(`./reference-v1/${id}.json`, import.meta.url), 'utf8'))));
const source = cases[0];
const portfolioBytes = await fs.readFile(new URL('./reference-v1/portfolio-reference.json', import.meta.url));
const portfolio = JSON.parse(portfolioBytes);
const portfolioHash = createHash('sha256').update(portfolioBytes).digest('hex');
assert.equal(portfolioHash, (await fs.readFile(new URL('./reference-v1/portfolio-reference.sha256', import.meta.url), 'utf8')).trim(), 'Resident portfolio source hash');
assert.equal(portfolio.schema_version, 1);
assert.equal(portfolio.treasury_maturity_weights.length, 120);
assert.ok(portfolio.treasury_maturity_weights.every(x => typeof x === 'number' && Number.isFinite(x) && x >= 0));
assert.ok(Math.abs(portfolio.treasury_maturity_weights.reduce((a, b) => a + b, 0) - 1) <= 1e-12);
for (const document of cases) {
  // Godot numeric formatting can lose source decimal digits; original bytes bind exactly.
  assert.equal(document.portfolio_reference_json, portfolioBytes.toString('utf8'), 'Exact native source JSON bytes');
  assert.deepEqual(JSON.parse(document.portfolio_reference_json), portfolio, 'Exact native portfolio source binding');
  assert.equal(document.portfolio_reference_sha256, portfolioHash);
}
const arrayShapes = { price_history: 5, treasury_cohorts_pct_initial_gdp: 120, sterilized_treasury_cohorts_pct_initial_gdp: 120, bill_cohorts_pct_initial_gdp: 4 };
const arrayField = (key, i) => key === 'price_history' ? `price_h${i}` : `${key}_${i}`;
const flattenState = state => Object.fromEntries(Object.entries(state).flatMap(([key, value]) => {
  if (!Array.isArray(value)) return [[key, value]];
  assert.equal(value.length, arrayShapes[key], `Native array schema: ${key}`);
  return value.map((item, i) => [arrayField(key, i), item]);
}));
const nominalKeys = new Set(['asset_flow_request_pct_initial_gdp', 'liquidity_request_pct_initial_gdp', 'funding_need_pct_initial_gdp', 'eligible_collateral_pct_initial_gdp', 'refinancing_need_pct_initial_gdp', 'rrp_encumbered_collateral_pct_initial_gdp']);
const nominalRatio = state => (state.actual_output_index / state.initial_actual_output_index) * (state.price_index / state.initial_price_index);
const shockDefault = key => key === 'potential_growth_pct' ? null : key === 'rrp_uptake_fraction' ? 1 : 0;
assert.equal(shockDefault('liquidity_eligibility_pct'), 0, 'Omitted liquidity eligibility must match native zero-access default');
const out = new URL('./', import.meta.url);
const evidence = new URL('./evidence/', import.meta.url);
const workbook = Workbook.create();
const [lab, policy, assumptions, economy, shocks] = ['Policy Lab', 'Policy', 'Assumptions', 'Economy', 'Shocks'].map(name => workbook.worksheets.add(name));
const C = { ink: '#203048', navy: '#233A56', blue: '#2257A0', amber: '#FFF2CC', pale: '#EAF0F6', muted: '#657286', red: '#AB3D35', copper: '#B07439', green: '#26735D' };
const column = n => { let s = ''; for (; n; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };
const cell = (sheet, address, value, formula = false) => { sheet.getRange(address)[formula ? 'formulas' : 'values'] = [[value]]; };
const human = key => key.replace(/_pct_initial_gdp$/, ' (% initial GDP)').replace(/_pct$/, ' (%)').replaceAll('_', ' ');
const clamp = (value, low, high) => `MIN(${high},MAX(${low},${value}))`;
const headers = (sheet, range) => { sheet.getRange(range).format = { fill: C.navy, font: { name: 'Arial', size: 10, bold: true, color: '#FFFFFF' }, rowHeight: 24 }; };
const input = (sheet, range) => { sheet.getRange(range).format.fill = C.amber; sheet.getRange(range).format.font.color = C.blue; };
for (const sheet of [lab, policy, assumptions, economy, shocks]) {
  sheet.showGridLines = false;
  sheet.getRange('A1:AZ150').format = { font: { name: 'Arial', size: 10, color: C.ink }, rowHeight: 22, columnWidth: 12, verticalAlignment: 'center' };
  sheet.getRange('A1:A150').format.columnWidth = 3;
  sheet.getRange('B1:B150').format.columnWidth = 40;
  sheet.getRange('C1:C150').format.columnWidth = 15;
  cell(sheet, 'B2', sheet.name === 'Policy Lab' ? 'Federal Reserve Policy Lab' : sheet.name);
  sheet.getRange('B2').format.font = { name: 'Arial', size: 16, color: C.navy, bold: true };
  sheet.getRange('B2:M2').format.borders = { bottom: { style: 'thin', color: C.copper } };
  if (sheet !== lab) {
    cell(sheet, 'B3', 'Case selected:');
    cell(sheet, 'D3', "='Policy Lab'!E4", true);
    sheet.getRange('D3:H3').format.borders = { preset: 'outside', style: 'dotted', color: C.muted };
    sheet.freezePanes.freezeRows(4);
    sheet.freezePanes.freezeColumns(3);
  }
}
lab.tabColor = C.navy;
policy.tabColor = C.blue;
assumptions.tabColor = '#A6B8CD';
cell(lab, 'B4', 'Case number'); cell(lab, 'C4', 3);
cell(lab, 'E4', `=CHOOSE(C4,${cases.map(x => `"${x.scenario.label}"`).join(',')})`, true);
cell(lab, 'B5', 'Quarter shown'); cell(lab, 'C5', 48);
cell(lab, 'B6', 'Benchmark policy'); cell(lab, 'C6', 1);
cell(lab, 'E6', '=CHOOSE(C6,"Feedback rule","Hold previous rate")', true);
input(lab, 'C4:C6');
for (const [address, max] of [['C4', cases.length], ['C5', 48], ['C6', 2]]) lab.getRange(address).dataValidation = { rule: { type: 'whole', operator: 'between', formula1: address === 'C5' ? 0 : 1, formula2: max } };
cell(lab, 'B8', 'Edit amber cells. Policy blanks use the selected benchmark; zero is an explicit decision.');
cell(lab, 'B9', 'Design assumptions, not a forecast. All cases include small seed-1 shocks.');
for (let n = 0; n < cases.length; n++) cell(lab, `J${4 + n}`, `${n + 1}. ${cases[n].scenario.label}`);

// Parameters have one editable value and a checked active value. Missing data stays unavailable.
assumptions.getRange('B5:F5').values = [['Parameter', 'Input', 'Active value', 'Unit', 'Classification']];
headers(assumptions, 'B5:F5');
const parameterRow = new Map(source.parameters.map((record, i) => [record.key, i + 6]));
const shares = /persistence|adjustment|fraction|_weight$|_share$/;
const unboundedWeights = new Set(['public_inflation_burden_weight', 'public_unemployment_burden_weight', 'public_hardship_memory_weight']);
for (let i = 0; i < source.parameters.length; i++) {
  const record = source.parameters[i], row = i + 6, ref = `C${row}`;
  cell(assumptions, `B${row}`, human(record.key)); cell(assumptions, ref, record.value);
  let domain = `ISNUMBER(${ref})`;
  if (record.classification === 'mathematical_identity' || record.key === 'inflation_target_pct') domain = `AND(${domain},${ref}=${record.value})`;
  else if ((shares.test(record.key) && !unboundedWeights.has(record.key)) || record.key === 'initial_credibility') domain = `AND(${domain},${ref}>=0,${ref}<=1)`;
  else if (record.key.includes('public_support')) domain = `AND(${domain},${ref}>=0,${ref}<=100)`;
  else if (record.key === 'initial_structural_unemployment_pct') domain = `AND(${domain},${ref}>0,${ref}<100)`;
  else if (record.key === 'initial_unemployment_pct') domain = `AND(${domain},${ref}>=0,${ref}<=100)`;
  else if (record.key === 'initial_policy_rate_pct') {
    const increment = `$D$${parameterRow.get('minimum_rate_increment_pct')}`;
    domain = `IF(AND(${domain},ISNUMBER(${increment})),ABS(${ref}/${increment}-ROUND(${ref}/${increment},0))<0.000001,FALSE)`;
  }
  else if (['initial_inflation_rate_pct', 'initial_expected_short_inflation_pct', 'initial_expected_long_inflation_pct'].includes(record.key)) domain = `AND(${domain},${ref}>-100)`;
  else if (/tolerance|_scale_pct|_increment_pct|initial_output_index|initial_price_index/.test(record.key) || ['portfolio_premium_max_shift_pct', 'treasury_duration_years', 'mbs_duration_years', 'reserve_clear_pct_current_gdp'].includes(record.key)) domain = `AND(${domain},${ref}>0)`;
  else if (/sensitivity|limit|capacity|normal_credit|burden_weight|hardship_memory_weight/.test(record.key)) domain = `AND(${domain},${ref}>=0)`;
  if (['initial_asset_stock_pct_initial_gdp', 'initial_currency_pct_initial_gdp', 'initial_treasury_account_pct_initial_gdp', 'normal_credit_spread_pct', 'policy_inflation_response', 'policy_output_gap_response'].includes(record.key)) domain = `AND(${domain},${ref}>=0)`;
  if (record.key === 'initial_output_gap_pct') domain = `AND(${domain},${ref}>-100)`;
  if (record.key === 'mbs_base_repayment_fraction') domain = `AND(${domain},${ref}>0,${ref}*(1+C${parameterRow.get('mbs_repayment_relative_response')})<=1)`;
  if (record.key === 'mbs_repayment_relative_response') domain = `AND(${domain},${ref}>=0,${ref}<1,C${parameterRow.get('mbs_base_repayment_fraction')}*(1+${ref})<=1)`;
  if (record.key === 'treasury_reinvestment_maturity_quarters') domain = `AND(${domain},${ref}>=1,${ref}<=120)`;
  if (record.key === 'reserve_buffer_pct_current_gdp') domain = `AND(${domain},${ref}>=C${parameterRow.get('reserve_clear_pct_current_gdp')})`;
  if (record.key === 'initial_reserves_pct_initial_gdp') domain = `AND(${domain},${ref}>=C${parameterRow.get('reserve_clear_pct_current_gdp')})`;
  if (record.key === 'demand_release_base_fraction') domain = `AND(${domain},${ref}<=C${parameterRow.get('demand_release_max_fraction')})`;
  if (record.key === 'demand_release_max_fraction') domain = `AND(${domain},${ref}+C${parameterRow.get('demand_cancellation_fraction')}<=1)`;
  cell(assumptions, `D${row}`, `=IF(${domain},${ref},NA())`, true);
  cell(assumptions, `E${row}`, record.unit); cell(assumptions, `F${row}`, record.classification.replaceAll('_', ' '));
  cell(assumptions, `H${row}`, record.description);
  if (record.source) cell(assumptions, `J${row}`, record.source);
  input(assumptions, ref);
}
assumptions.getRange('E5:E150').format.columnWidth = 31;
assumptions.getRange('F5:F150').format.columnWidth = 22;
assumptions.getRange('H5:H150').format.columnWidth = 110;
assumptions.getRange('J5:J150').format.columnWidth = 85;
assumptions.getRange(`B6:J${source.parameters.length + 5}`).format.wrapText = true;
assumptions.getRange(`B6:J${source.parameters.length + 5}`).format.rowHeight = 48;
const p = key => { assert.ok(parameterRow.has(key), `Unknown parameter ${key}`); return `'Assumptions'!$D$${parameterRow.get(key)}`; };
// Artifact Tool ROUND uses a different negative-tie rule; the positive magnitude is portable.
const quote = value => `SIGN(${value})*ROUND(ABS(${value})/${p('minimum_rate_increment_pct')},0)*${p('minimum_rate_increment_pct')}`;
const onGrid = value => `IF(ISNUMBER(${value}),ABS(${value}/${p('minimum_rate_increment_pct')}-ROUND(${value}/${p('minimum_rate_increment_pct')},0))<0.000001,FALSE)`;
const effective = value => `IF(ISNUMBER(${p('negative_rate_efficacy_scale_pct')}),IF(${value}>=0,${value},${p('negative_rate_efficacy_scale_pct')}*TANH(${value}/${p('negative_rate_efficacy_scale_pct')})),NA())`;
const weightsRow = source.parameters.length + 9;
cell(assumptions, `B${weightsRow - 1}`, 'Credibility weights (fixed in core)');
for (const [i, label, value] of [[0, 'Inflation performance', 0.4], [1, 'Stance adequacy', 0.4], [2, 'Conditional follow-through', 0.2]]) {
  cell(assumptions, `B${weightsRow + i}`, label); cell(assumptions, `D${weightsRow + i}`, value);
}
cell(assumptions, `H${weightsRow}`, 'The 40/40/20 rule is a game-design assumption, not an estimated Federal Reserve objective.');
cell(assumptions, `H${weightsRow + 2}`, 'Public support is a fictional score with gradual recovery, not a legal dismissal threshold.');

const initialParameter = {
  output_gap_pct: 'initial_output_gap_pct', annualized_quarterly_inflation_pct: 'initial_inflation_rate_pct',
  expected_short_inflation_pct: 'initial_expected_short_inflation_pct', expected_long_inflation_pct: 'initial_expected_long_inflation_pct',
  policy_rate_pct: 'initial_policy_rate_pct', unemployment_rate_pct: 'initial_unemployment_pct', credibility: 'initial_credibility',
  public_support: 'initial_public_support', r_star_pct: 'initial_r_star_pct', structural_unemployment_pct: 'initial_structural_unemployment_pct',
  asset_stock_pct_initial_gdp: 'initial_asset_stock_pct_initial_gdp', term_premium_pct: 'initial_term_premium_pct',
};
const initialRows = new Map();
const initialFields = [...new Set([...Object.keys(initialParameter), ...cases.flatMap(x => Object.keys(x.scenario.initial)), 'supply_pressure_pct', 'solvency_risk_wedge_pct', 'public_hardship_memory', 'deferred_demand_pct', 'r_star_reference_pct'])];
const caseStride = cases.length + 2;
let initialRow = weightsRow + 8;
for (const key of initialFields) {
  initialRows.set(key, initialRow);
  cell(assumptions, `B${initialRow}`, `${human(key)}: active`);
  const choices = cases.map((_, i) => `D${initialRow + i + 1}`).join(',');
  const present = cases.map((_, i) => `ISNUMBER(D${initialRow + i + 1})`).join(',');
  const selected = `CHOOSE('Policy Lab'!$C$4,${choices})`;
  const numeric = `CHOOSE('Policy Lab'!$C$4,${present})`;
  const valid = key === 'unemployment_rate_pct' ? `AND(${numeric},${selected}>=0,${selected}<=100)`
    : ['annualized_quarterly_inflation_pct', 'expected_short_inflation_pct', 'expected_long_inflation_pct'].includes(key) ? `AND(${numeric},${selected}>-100)`
    : key === 'policy_rate_pct' ? `AND(${numeric},${onGrid(selected)})`
    : key === 'output_gap_pct' ? `AND(${numeric},${selected}>-100)`
    : ['asset_stock_pct_initial_gdp', 'supply_pressure_pct', 'solvency_risk_wedge_pct', 'public_hardship_memory'].includes(key) && key !== 'supply_pressure_pct' ? `AND(${numeric},${selected}>=0)`
    : key === 'credibility' ? `AND(${numeric},${selected}>=0,${selected}<=1)`
    : key === 'public_support' ? `AND(${numeric},${selected}>=0,${selected}<=100)`
    : key === 'structural_unemployment_pct' ? `AND(${numeric},${selected}>0,${selected}<100)` : numeric;
  cell(assumptions, `D${initialRow}`, `=IF(${valid},${selected},NA())`, true);
  assumptions.getRange(`B${initialRow}:F${initialRow}`).format.fill = C.pale;
  for (let i = 0; i < cases.length; i++) {
    const row = initialRow + i + 1, value = cases[i].scenario.initial[key];
    cell(assumptions, `B${row}`, cases[i].scenario.label);
    if (value === undefined) cell(assumptions, `D${row}`, `=${initialParameter[key] ? p(initialParameter[key]) : key === 'r_star_reference_pct' ? `D${initialRows.get('r_star_pct') + i + 1}` : '0'}`, true);
    else { cell(assumptions, `D${row}`, value); input(assumptions, `D${row}`); }
  }
  initialRow += caseStride;
}
const initial = key => initialRows.has(key) ? `'Assumptions'!$D$${initialRows.get(key)}` : initialParameter[key] ? p(initialParameter[key]) : '0';

const shockKeys = ['demand_shock_pct', 'supply_innovation_pct', 'potential_growth_pct', 'r_star_change_pct', 'r_star_reference_change_pct', 'structural_unemployment_change_pct', 'funding_need_pct_initial_gdp', 'eligible_collateral_pct_initial_gdp', 'collateral_haircut_pct', 'liquidity_eligibility_pct', 'credit_risk_innovation_pct', 'solvency_risk_innovation_pct', 'refinancing_need_pct_initial_gdp', 'rrp_uptake_fraction', 'rrp_encumbered_collateral_pct_initial_gdp'];
const shockRows = new Map();
for (let i = 0; i < shockKeys.length; i++) {
  const key = shockKeys[i], row = 6 + i * caseStride;
  shockRows.set(key, row);
  cell(shocks, `B${row}`, `${human(key)}: active`);
  shocks.getRange(`B${row}:AZ${row}`).format.fill = C.pale;
  for (let n = 0; n < cases.length; n++) {
    cell(shocks, `B${row + n + 1}`, cases[n].scenario.label);
    shocks.getRange(`E${row + n + 1}:AZ${row + n + 1}`).values = [cases[n].shock_path.map(x => x[key] ?? shockDefault(key))];
    input(shocks, `E${row + n + 1}:AZ${row + n + 1}`);
  }
  const formulas = Array.from({ length: 48 }, (_, q) => {
    const col = column(q + 5), refs = cases.map((_, n) => `${col}${row + n + 1}`);
    const choose = values => `CHOOSE('Policy Lab'!$C$4,${values.join(',')})`;
    const limit = { rrp_uptake_fraction: 1, demand_shock_pct: 10, supply_innovation_pct: 5, potential_growth_pct: 20, r_star_change_pct: 1, r_star_reference_change_pct: 1, structural_unemployment_change_pct: 0.5, credit_risk_innovation_pct: 5, solvency_risk_innovation_pct: 5 }[key] ?? 100;
    const signed = ['demand_shock_pct', 'supply_innovation_pct', 'potential_growth_pct', 'r_star_change_pct', 'r_star_reference_change_pct', 'structural_unemployment_change_pct'].includes(key);
    const valid = choose(refs.map(ref => `AND(ISNUMBER(${ref}),${ref}>=${signed ? -limit : 0}${nominalKeys.has(key) ? '' : `,${ref}<=${limit}`})`));
    const numeric = `IF(${valid},${choose(refs)},NA())`;
    return `=${key === 'potential_growth_pct' ? `IF(${choose(refs.map(ref => `ISBLANK(${ref})`))},"unchanged",${numeric})` : numeric}`;
  });
  shocks.getRange(`E${row}:AZ${row}`).formulas = [formulas];
}
const shockNoteRow = 6 + shockKeys.length * caseStride;
cell(shocks, `B${shockNoteRow}`, 'Seed 1 realized paths from Godot 4.7.2. Hypothetical disturbances; no historical calibration.');
cell(shocks, `B${shockNoteRow + 1}`, 'Blank potential growth keeps the previous trend. All other active shock inputs must be numeric.');
cell(shocks, `B${shockNoteRow + 2}`, `Recurring crises: ${cases.find(x => x.scenario.id === 'mixed_crises').scenario.description}`);
shocks.getRange(`E6:AZ${shockNoteRow - 2}`).setNumberFormat('0.000');

const R = {
  quarter_index: 4, potential_output_index: 5, actual_output_index: 6, annualized_actual_growth_pct: 7,
  annualized_potential_growth_pct: 8, output_gap_pct: 9, potential_growth_pct: 10, price_index: 11,
  annualized_quarterly_inflation_pct: 12, four_quarter_inflation_pct: 13, expected_short_inflation_pct: 14,
  expected_long_inflation_pct: 15, unemployment_rate_pct: 16, structural_unemployment_pct: 17, r_star_pct: 18,
  last_policy_rate_request_pct: 19, policy_rate_pct: 20, long_yield_pct: 21, financial_restraint_gap_pct: 22,
  asset_flow_request_pct_initial_gdp: 23, asset_flow_applied_pct_initial_gdp: 24, asset_stock_pct_initial_gdp: 25,
  initial_asset_stock_pct_initial_gdp: 26, term_premium_pct: 28,
  funding_need_pct_initial_gdp: 29, eligible_collateral_pct_initial_gdp: 30, outstanding_liquidity_pct_initial_gdp: 31,
  liquidity_repayment_pct_initial_gdp: 32, liquidity_request_pct_initial_gdp: 33, liquidity_applied_pct_initial_gdp: 34,
  uncovered_funding_pct_initial_gdp: 35, credit_spread_pct: 36, credit_risk_wedge_pct: 37, solvency_risk_wedge_pct: 38,
  supply_pressure_pct: 39, credibility: 40, inflation_miss_memory_pct: 41, guidance_active: 42,
  guidance_rate_pct: 43, guidance_inflation_sensitivity: 44, guidance_output_gap_sensitivity: 45,
  guidance_reference_inflation_pct: 46, guidance_reference_output_gap_pct: 47, guidance_followthrough_score: 48,
  reaction_function_target_pct: 49, public_support: 50, public_hardship_memory: 51, current_hardship: 52,
  initial_annual_gdp_index: 53, price_h0: 54, price_h1: 55, price_h2: 56, price_h3: 57, price_h4: 58,
  prior_commitment: 60, priced_guidance: 61, expected_policy_path: 62, spot_financial_gap_pct: 63, inflation_pressure: 64,
  long_anchor: 65, inflation_performance: 66, stance_adequacy_score: 67, credibility_score: 68, support_target: 69,
  policy_valid: 73, benchmark_rate: 75,
  deferred_demand_pct: 77, demand_release_pct: 78, r_star_reference_pct: 79, underlying_gap: 80,
  available_demand: 81, release_fraction: 82, recent_expectation_base: 83, short_anchor_weight: 84,
  effective_policy_rate_pct: 85, effective_priced_guidance_pct: 86, stance_target_gap_pct: 87,
  stance_distance_pct: 88, stance_best_feasible_distance_pct: 89, floor_guide_pct: 90,
  floor_long_yield_pct: 91, floor_spot_gap_pct: 92, upward_rate_loading: 93,
};
let nextModelRow = 100;
const register = key => { if (!R[key]) R[key] = nextModelRow++; return R[key]; };
for (const key of Object.keys(flattenState(source.initial_state))) register(key);
for (const key of ['reinvest_principal', 'maintain_ample_reserves', 'sterilize_purchases', 'runoff_share', 'reinvest_share', 'tagged_due', 'uptake_absorption', 'local_after_absorption', 'settlement_reserves', 'duration_difference', 'premium_log_ratio', 'ending_securities_pct_current_gdp', 'ending_reserves_pct_current_gdp', 'ending_loans_pct_current_gdp', 'ending_rrp_pct_current_gdp']) register(key);
const sourceStart = initialRow + 5;
cell(assumptions, `B${sourceStart - 4}`, 'Observed Treasury principal (USD)'); cell(assumptions, `C${sourceStart - 4}`, Number(portfolio.source_treasury_principal_usd));
cell(assumptions, `B${sourceStart - 3}`, 'Observed MBS stock (billion USD)'); cell(assumptions, `C${sourceStart - 3}`, portfolio.mbs_stock_billion_usd);
cell(assumptions, `B${sourceStart - 2}`, 'Initial Treasury share: source principal');
cell(assumptions, `D${sourceStart - 2}`, `=IF(AND(ISNUMBER(C${sourceStart - 4}),C${sourceStart - 4}>0,ISNUMBER(C${sourceStart - 3}),C${sourceStart - 3}>0),C${sourceStart - 4}/(C${sourceStart - 4}+C${sourceStart - 3}*1000000000),NA())`, true);
cell(assumptions, `B${sourceStart - 1}`, 'Source ladder valid (120 model-quarter bins)');
cell(assumptions, `D${sourceStart - 1}`, `=AND(COUNT(C${sourceStart}:C${sourceStart + 119})=120,MIN(C${sourceStart}:C${sourceStart + 119})>=0,ABS(SUM(C${sourceStart}:C${sourceStart + 119})-1)<=0.000000000001)`, true);
for (const [i, weight] of portfolio.treasury_maturity_weights.entries()) {
  cell(assumptions, `B${sourceStart + i}`, `Treasury principal due in model quarter ${i + 1}`);
  cell(assumptions, `C${sourceStart + i}`, weight);
  cell(assumptions, `D${sourceStart + i}`, `=IF($D$${sourceStart - 1},C${sourceStart + i},NA())`, true);
}
for (const [i, [key, value]] of Object.entries(portfolio).filter(([key]) => key !== 'treasury_maturity_weights').entries()) {
  cell(assumptions, `H${sourceStart + i}`, human(key)); cell(assumptions, `J${sourceStart + i}`, value);
}
cell(assumptions, `H${sourceStart - 1}`, 'Portfolio reference SHA256'); cell(assumptions, `J${sourceStart - 1}`, portfolioHash);
assumptions.getRange(`B${sourceStart - 4}:J${sourceStart + 119}`).format = { font: { name: 'Arial', size: 10, color: C.ink }, rowHeight: 22, verticalAlignment: 'center' };
assumptions.getRange(`B${sourceStart - 4}:B${sourceStart + 119}`).format.columnWidth = 54;
assumptions.getRange(`H${sourceStart - 1}:J${sourceStart + 20}`).format.wrapText = true;
assumptions.getRange(`H${sourceStart - 1}:J${sourceStart + 20}`).format.rowHeight = 48;
for (const [key, row] of Object.entries(R)) cell(economy, `B${row}`, human(key));
cell(economy, 'B64', 'Annual gross price growth');
for (const [row, label] of [
  [77, 'Deferred demand (% potential)'], [78, 'Demand release (pp)'],
  [79, 'Neutral structural reference (%)'], [80, 'Activity before catch-up (pp)'],
  [81, 'Rebased backlog (% potential)'], [82, 'Release fraction'],
  [83, 'Recent expected gross factor'], [84, 'Credibility-weighted long anchor'],
  [85, 'Effective policy rate (%)'], [86, 'Effective priced guidance (%)'],
  [87, 'Desired real restraint (pp)'], [88, 'Actual stance distance (pp)'],
  [89, 'Transmission-frontier shortfall (pp)'], [90, 'Guidance lower limit (%)'],
  [91, 'Long-yield lower limit (%)'], [92, 'Real-restraint lower limit (pp)'],
  [93, 'Upward current-rate loading'],
]) cell(economy, `B${row}`, label);
headers(economy, 'B4:AZ4');
economy.getRange('D5:AZ93').setNumberFormat('0.000');
const f = (col, key) => { assert.ok(R[key], `Unmapped formula field ${key}`); return `${col}${R[key]}`; };
// Same rate equations at the initial state and each transition, with prior observations explicit.
const writeRateConditions = (s, prior, put) => {
  const scale = p('negative_rate_efficacy_scale_pct'), current = p('long_yield_current_rate_weight'), short = p('real_rate_short_weight');
  put('effective_policy_rate_pct', effective(s('policy_rate_pct')));
  put('priced_guidance', `${s('policy_rate_pct')}+${prior('credibility')}*(${s('guidance_rate_pct')}-${s('policy_rate_pct')})`);
  put('effective_priced_guidance_pct', effective(s('priced_guidance')));
  put('expected_policy_path', `${current}*${s('effective_policy_rate_pct')}+(1-${current})*${s('effective_priced_guidance_pct')}`);
  put('long_yield_pct', `${s('expected_policy_path')}+${s('term_premium_pct')}`);
  const realGap = (rate, yieldValue) => `${short}*(${rate}-${prior('expected_short_inflation_pct')})+(1-${short})*(${yieldValue}-${p('initial_term_premium_pct')}-${prior('expected_long_inflation_pct')})+(${s('credit_spread_pct')}-${p('normal_credit_spread_pct')})-${s('r_star_pct')}`;
  put('spot_financial_gap_pct', realGap(s('effective_policy_rate_pct'), s('long_yield_pct')));
  put('stance_target_gap_pct', `${p('policy_inflation_response')}*(${prior('four_quarter_inflation_pct')}-${p('inflation_target_pct')})+${p('policy_output_gap_response')}*${prior('output_gap_pct')}`);
  put('floor_guide_pct', `IF(${prior('credibility')}=1,${effective(s('guidance_rate_pct'))},-${scale})`);
  put('floor_long_yield_pct', `-${current}*${scale}+(1-${current})*${s('floor_guide_pct')}+${s('term_premium_pct')}`);
  put('floor_spot_gap_pct', realGap(`-${scale}`, s('floor_long_yield_pct')));
  put('upward_rate_loading', `${short}+(1-${short})*(${current}+(1-${current})*(1-${prior('credibility')}))`);
  put('stance_distance_pct', `ABS(${s('spot_financial_gap_pct')}-${s('stance_target_gap_pct')})`);
  put('stance_best_feasible_distance_pct', `IF(${s('upward_rate_loading')}=0,${s('stance_distance_pct')},MAX(0,${s('floor_spot_gap_pct')}-${s('stance_target_gap_pct')}))`);
  const tolerance = p('credibility_stance_scale_pct');
  put('stance_adequacy_score', `EXP(-MAX(0,${s('stance_distance_pct')}-${s('stance_best_feasible_distance_pct')})/${tolerance})*${tolerance}/(${tolerance}+${s('stance_best_feasible_distance_pct')})`);
  put('reaction_function_target_pct', `${s('r_star_pct')}+${prior('expected_short_inflation_pct')}+${s('stance_target_gap_pct')}`);
};
// Scalar cancellation follows the native principal-net helper without summing huge
// opposite gross legs first. Helpers are visible in the same calculation chain.
const principalNet = (label, legs, s, put) => {
  const n = legs.length, key = suffix => `net_${label}_${suffix}`;
  const emit = (suffix, formula) => { register(key(suffix)); put(key(suffix), formula); return s(key(suffix)); };
  const credits = legs.map((leg, i) => emit(`credit_${i}`, `MAX(0,${leg})`));
  const debits = legs.map((leg, i) => emit(`debit_${i}`, `MAX(0,-(${leg}))`));
  const cr = `${credits[0]}:${credits.at(-1)}`, dr = `${debits[0]}:${debits.at(-1)}`;
  let ci = emit('ci_0', '1'), di = emit('di_0', '1');
  let c = emit('c_0', `LARGE(${cr},1)`), d = emit('d_0', `LARGE(${dr},1)`);
  for (let i = 1; i <= n; i++) {
    const stopped = `OR(${c}=0,${d}=0)`;
    const nc = emit(`ci_${i}`, `IF(${stopped},${ci},${ci}+IF(${c}<=${d},1,0))`);
    const nd = emit(`di_${i}`, `IF(${stopped},${di},${di}+IF(${d}<=${c},1,0))`);
    const cc = emit(`c_${i}`, `IF(${stopped},${c},IF(${c}>${d},${c}-${d},IF(${nc}>${n},0,LARGE(${cr},${nc}))))`);
    const dd = emit(`d_${i}`, `IF(${stopped},${d},IF(${d}>${c},${d}-${c},IF(${nd}>${n},0,LARGE(${dr},${nd}))))`);
    ci = nc; di = nd; c = cc; d = dd;
  }
  const rest = (range, index) => Array.from({ length: n }, (_, k) => `IF(${k + 1}>${index},LARGE(${range},${k + 1}),0)`).reverse();
  return emit('result', `SUM(${rest(cr, ci).join(',')},${c})-SUM(${rest(dr, di).join(',')},${d})`);
};
const cohortSum = (s, key, count) => `SUM(${s(arrayField(key, 0))}:${s(arrayField(key, count - 1))})`;
const treasuryKey = 'treasury_cohorts_pct_initial_gdp', tagKey = 'sterilized_treasury_cohorts_pct_initial_gdp', billKey = 'bill_cohorts_pct_initial_gdp';
const writeBalance = (s, prev, shock, put) => {
  const net = (label, legs) => principalNet(label, legs, s, put);
  put('mbs_repayment_fraction', `${p('mbs_base_repayment_fraction')}*(1+${p('mbs_repayment_relative_response')}*TANH((${prev('initial_mbs_financing_rate_pct')}-(${prev('long_yield_pct')}+${prev('credit_spread_pct')}))/${p('mbs_repayment_rate_scale_pct')}))`);
  put('treasury_redemption_pct_initial_gdp', prev(arrayField(treasuryKey, 0)));
  put('mbs_repayment_pct_initial_gdp', `${prev('mbs_stock_pct_initial_gdp')}*${s('mbs_repayment_fraction')}`);
  put('bill_redemption_pct_initial_gdp', prev(arrayField(billKey, 0)));
  put('principal_due_pct_initial_gdp', `${s('treasury_redemption_pct_initial_gdp')}+${s('mbs_repayment_pct_initial_gdp')}+${s('bill_redemption_pct_initial_gdp')}`);
  put('discretionary_purchase_pct_initial_gdp', `MAX(0,${s('asset_flow_request_pct_initial_gdp')})`);
  put('principal_runoff_pct_initial_gdp', `IF(${s('asset_flow_request_pct_initial_gdp')}<0,MIN(-${s('asset_flow_request_pct_initial_gdp')},${s('principal_due_pct_initial_gdp')}),IF(${s('reinvest_principal')},0,${s('principal_due_pct_initial_gdp')}))`);
  put('runoff_share', `IF(${s('principal_due_pct_initial_gdp')}>0,${s('principal_runoff_pct_initial_gdp')}/${s('principal_due_pct_initial_gdp')},0)`);
  put('reinvest_share', `1-${s('runoff_share')}`);
  put('principal_reinvestment_pct_initial_gdp', `${s('principal_due_pct_initial_gdp')}-${s('principal_runoff_pct_initial_gdp')}`);
  for (const [target, due] of [['treasury_reinvestment_pct_initial_gdp', 'treasury_redemption_pct_initial_gdp'], ['mbs_reinvestment_pct_initial_gdp', 'mbs_repayment_pct_initial_gdp'], ['bill_rollover_pct_initial_gdp', 'bill_redemption_pct_initial_gdp']]) put(target, `${s(due)}*${s('reinvest_share')}`);
  put('long_securities_runoff_pct_initial_gdp', `${s('treasury_redemption_pct_initial_gdp')}*${s('runoff_share')}+${s('mbs_repayment_pct_initial_gdp')}*${s('runoff_share')}`);
  put('mbs_stock_pct_initial_gdp', `${prev('mbs_stock_pct_initial_gdp')}-${s('mbs_repayment_pct_initial_gdp')}*${s('runoff_share')}`);
  put('tagged_due', `IF(${s('sterilize_purchases')},${prev(arrayField(tagKey, 0))},0)`);
  put('sterilized_principal_runoff_pct_initial_gdp', `${s('tagged_due')}*${s('runoff_share')}`);
  put('sterilized_principal_reinvestment_pct_initial_gdp', `${s('tagged_due')}*${s('reinvest_share')}`);
  const maturity = p('treasury_reinvestment_maturity_quarters');
  const binWeight = i => `IF(${i}=INT(${maturity})-1,1-(${maturity}-INT(${maturity})),IF(${i}=INT(${maturity}),${maturity}-INT(${maturity}),0))`;
  for (let i = 0; i < 120; i++) {
    put(arrayField(treasuryKey, i), `${i < 119 ? prev(arrayField(treasuryKey, i + 1)) : '0'}+${s('treasury_reinvestment_pct_initial_gdp')}*${binWeight(i)}+${s('discretionary_purchase_pct_initial_gdp')}*${binWeight(i)}`);
    put(arrayField(tagKey, i), `IF(${s('sterilize_purchases')},${i < 119 ? prev(arrayField(tagKey, i + 1)) : '0'}+${s('sterilized_principal_reinvestment_pct_initial_gdp')}*${binWeight(i)}+${s('discretionary_purchase_pct_initial_gdp')}*${binWeight(i)},0)`);
  }
  // Maintenance is added only to the fourth bill bin after joint funding clears.
  for (let i = 0; i < 3; i++) put(arrayField(billKey, i), prev(arrayField(billKey, i + 1)));
  put('sterilization_requested_pct_initial_gdp', cohortSum(s, tagKey, 120));
  put('sterilization_uptake_fraction', shock('rrp_uptake_fraction'));
  put('sterilization_collateral_available_pct_initial_gdp', `MAX(0,${net('rrp_collateral', [cohortSum(s, treasuryKey, 120), `${s(arrayField(billKey, 0))}+${s(arrayField(billKey, 1))}+${s(arrayField(billKey, 2))}+${s('bill_rollover_pct_initial_gdp')}`, `-${s(arrayField(treasuryKey, 0))}`, `-${s(arrayField(billKey, 0))}`, `-${shock('rrp_encumbered_collateral_pct_initial_gdp')}`])})`);
  put('uptake_absorption', `${s('sterilization_requested_pct_initial_gdp')}*${s('sterilization_uptake_fraction')}`);
  put('sterilization_planned_pct_initial_gdp', `MIN(${s('uptake_absorption')},${s('sterilization_collateral_available_pct_initial_gdp')})`);
  put('currency_pct_initial_gdp', `${p('initial_currency_pct_initial_gdp')}*${s('decision_nominal_gdp_ratio')}`);
  put('currency_conversion_pct_initial_gdp', `${s('currency_pct_initial_gdp')}-${prev('currency_pct_initial_gdp')}`);
  put('liquidity_repayment_pct_initial_gdp', prev('outstanding_liquidity_pct_initial_gdp'));
  put('reverse_repo_closed_pct_initial_gdp', prev('reverse_repo_pct_initial_gdp'));
  put('reserves_before_accommodation_pct_initial_gdp', net('reserve_base', [prev('reserves_pct_initial_gdp'), prev('reverse_repo_pct_initial_gdp'), s('discretionary_purchase_pct_initial_gdp'), `-${s('principal_runoff_pct_initial_gdp')}`, `-${s('liquidity_repayment_pct_initial_gdp')}`, `-${s('currency_conversion_pct_initial_gdp')}`]));
  put('funding_need_pct_initial_gdp', shock('funding_need_pct_initial_gdp'));
  put('eligible_collateral_pct_initial_gdp', shock('eligible_collateral_pct_initial_gdp'));
  put('refinancing_request_pct_initial_gdp', shock('refinancing_need_pct_initial_gdp'));
  put('refinancing_need_pct_initial_gdp', `MIN(${s('refinancing_request_pct_initial_gdp')},${s('liquidity_repayment_pct_initial_gdp')})`);
  put('lending_collateral_capacity_pct_initial_gdp', `${s('eligible_collateral_pct_initial_gdp')}*(1-${shock('collateral_haircut_pct')}/100)*${shock('liquidity_eligibility_pct')}/100`);
  put('eligible_local_need_pct_initial_gdp', `${s('refinancing_need_pct_initial_gdp')}*${shock('liquidity_eligibility_pct')}/100+${s('funding_need_pct_initial_gdp')}*${shock('liquidity_eligibility_pct')}/100`);
  put('liquidity_local_applied_pct_initial_gdp', `MIN(${s('liquidity_request_pct_initial_gdp')},MIN(${s('lending_collateral_capacity_pct_initial_gdp')},${s('eligible_local_need_pct_initial_gdp')}))`);
  put('liquidity_refinancing_applied_pct_initial_gdp', `MIN(${s('liquidity_local_applied_pct_initial_gdp')},${s('refinancing_need_pct_initial_gdp')}*${shock('liquidity_eligibility_pct')}/100)`);
  put('liquidity_new_need_applied_pct_initial_gdp', `${s('liquidity_local_applied_pct_initial_gdp')}-${s('liquidity_refinancing_applied_pct_initial_gdp')}`);
  put('uncovered_new_funding_pct_initial_gdp', `${s('funding_need_pct_initial_gdp')}-${s('liquidity_new_need_applied_pct_initial_gdp')}`);
  put('uncovered_refinancing_pct_initial_gdp', `${s('refinancing_need_pct_initial_gdp')}-${s('liquidity_refinancing_applied_pct_initial_gdp')}`);
  put('uncovered_funding_pct_initial_gdp', `${s('uncovered_new_funding_pct_initial_gdp')}+${s('uncovered_refinancing_pct_initial_gdp')}`);
  put('reserve_buffer_pct_initial_gdp', `${p('reserve_buffer_pct_current_gdp')}*${s('decision_nominal_gdp_ratio')}`);
  put('reserve_clear_pct_initial_gdp', `${p('reserve_clear_pct_current_gdp')}*${s('decision_nominal_gdp_ratio')}`);
  put('local_after_absorption', net('local_after_absorption', [s('reserves_before_accommodation_pct_initial_gdp'), s('liquidity_local_applied_pct_initial_gdp'), `-${s('sterilization_planned_pct_initial_gdp')}`]));
  put('reserve_maintenance_purchase_pct_initial_gdp', `IF(${s('maintain_ample_reserves')},MAX(0,${net('maintenance', [s('reserve_buffer_pct_initial_gdp'), `-${s('local_after_absorption')}`])}),0)`);
  put('liquidity_aggregate_need_pct_initial_gdp', `IF(${s('maintain_ample_reserves')},0,MAX(0,${net('aggregate_need', [s('reserve_clear_pct_initial_gdp'), `-${s('local_after_absorption')}`])}))`);
  put('liquidity_aggregate_applied_pct_initial_gdp', `IF(${s('maintain_ample_reserves')},0,MIN(MAX(0,${s('liquidity_request_pct_initial_gdp')}-${s('liquidity_local_applied_pct_initial_gdp')}),MIN(MAX(0,${s('lending_collateral_capacity_pct_initial_gdp')}-${s('liquidity_local_applied_pct_initial_gdp')}),${s('liquidity_aggregate_need_pct_initial_gdp')})))`);
  put('sterilization_applied_pct_initial_gdp', `IF(${s('maintain_ample_reserves')},${s('sterilization_planned_pct_initial_gdp')},MIN(${s('sterilization_planned_pct_initial_gdp')},MAX(0,${net('absorption_reserves', [s('reserves_before_accommodation_pct_initial_gdp'), s('liquidity_local_applied_pct_initial_gdp'), s('liquidity_aggregate_applied_pct_initial_gdp')])})))`);
  put('settlement_reserves', net('reserve_final', [s('reserves_before_accommodation_pct_initial_gdp'), s('liquidity_local_applied_pct_initial_gdp'), s('liquidity_aggregate_applied_pct_initial_gdp'), `-${s('sterilization_applied_pct_initial_gdp')}`, s('reserve_maintenance_purchase_pct_initial_gdp')]));
  put('reserves_pct_initial_gdp', `IF(AND(${s('settlement_reserves')}>=0,${prev('treasury_account_pct_initial_gdp')}>=0),${s('settlement_reserves')},NA())`);
  put(arrayField(billKey, 3), `${s('bill_rollover_pct_initial_gdp')}+${s('reserve_maintenance_purchase_pct_initial_gdp')}`);
  put('reverse_repo_pct_initial_gdp', s('sterilization_applied_pct_initial_gdp'));
  put('outstanding_liquidity_pct_initial_gdp', `${s('liquidity_local_applied_pct_initial_gdp')}+${s('liquidity_aggregate_applied_pct_initial_gdp')}`);
  put('liquidity_applied_pct_initial_gdp', s('outstanding_liquidity_pct_initial_gdp'));
  put('asset_stock_pct_initial_gdp', net('securities', [prev('asset_stock_pct_initial_gdp'), s('discretionary_purchase_pct_initial_gdp'), `-${s('principal_runoff_pct_initial_gdp')}`, s('reserve_maintenance_purchase_pct_initial_gdp')]));
  put('asset_flow_applied_pct_initial_gdp', `${s('discretionary_purchase_pct_initial_gdp')}-${s('principal_runoff_pct_initial_gdp')}`);
  put('total_assets_pct_initial_gdp', `${s('asset_stock_pct_initial_gdp')}+${s('outstanding_liquidity_pct_initial_gdp')}`);
  put('total_asset_change_pct_initial_gdp', `${s('total_assets_pct_initial_gdp')}-${prev('total_assets_pct_initial_gdp')}`);
  put('principal_ledger_error_pct_initial_gdp', net('ledger', [s('total_assets_pct_initial_gdp'), `-${s('reserves_pct_initial_gdp')}`, `-${s('reverse_repo_pct_initial_gdp')}`, `-${s('currency_pct_initial_gdp')}`, `-${prev('treasury_account_pct_initial_gdp')}`, `-${prev('capital_other_pct_initial_gdp')}`]));
  put('reserve_scarcity_wedge_pct', `IF(${s('reserves_pct_initial_gdp')}>=${s('reserve_clear_pct_initial_gdp')},0,${p('reserve_scarcity_sensitivity_pct')}*POWER(1-${s('reserves_pct_initial_gdp')}/${s('reserve_clear_pct_initial_gdp')},2))`);
  put('local_access_wedge_pct', `${p('funding_spread_sensitivity')}*${s('uncovered_funding_pct_initial_gdp')}`);
  put('duration_equivalent_pct_initial_gdp', `${cohortSum(s, treasuryKey, 120)}+${s('mbs_stock_pct_initial_gdp')}*(${p('mbs_duration_years')}/${p('treasury_duration_years')})`);
  put('duration_difference', `${s('duration_equivalent_pct_initial_gdp')}-${s('initial_duration_equivalent_pct_initial_gdp')}`);
  put('premium_log_ratio', `IF(${s('duration_difference')}=0,0,LN(ABS(${s('duration_difference')}))-LN(${s('decision_nominal_gdp_ratio')})-LN(${p('portfolio_premium_scale_pct_gdp')}))`);
  put('term_premium_pct', `IF(${s('duration_difference')}=0,${s('initial_portfolio_premium_pct')},${s('initial_portfolio_premium_pct')}-${p('portfolio_premium_max_shift_pct')}*IF(${s('premium_log_ratio')}>LN(20),SIGN(${s('duration_difference')}),TANH(SIGN(${s('duration_difference')})*EXP(${s('premium_log_ratio')}))))`);
  for (const key of ['treasury', 'bill']) put(`${key}_funding_transfer_pct_initial_gdp`, s(`${key}_redemption_pct_initial_gdp`));
  for (const [key, condition] of [
    ['liquidity_offer_binding', `${s('liquidity_local_applied_pct_initial_gdp')}<${s('eligible_local_need_pct_initial_gdp')},${s('liquidity_local_applied_pct_initial_gdp')}=${s('liquidity_request_pct_initial_gdp')}`],
    ['liquidity_collateral_binding', `${s('liquidity_local_applied_pct_initial_gdp')}<${s('eligible_local_need_pct_initial_gdp')},${s('liquidity_local_applied_pct_initial_gdp')}=${s('lending_collateral_capacity_pct_initial_gdp')}`],
    ['liquidity_aggregate_offer_binding', `${s('liquidity_aggregate_applied_pct_initial_gdp')}<${s('liquidity_aggregate_need_pct_initial_gdp')},${s('liquidity_aggregate_applied_pct_initial_gdp')}=MAX(0,${s('liquidity_request_pct_initial_gdp')}-${s('liquidity_local_applied_pct_initial_gdp')})`],
    ['liquidity_aggregate_collateral_binding', `${s('liquidity_aggregate_applied_pct_initial_gdp')}<${s('liquidity_aggregate_need_pct_initial_gdp')},${s('liquidity_aggregate_applied_pct_initial_gdp')}=MAX(0,${s('lending_collateral_capacity_pct_initial_gdp')}-${s('liquidity_local_applied_pct_initial_gdp')})`],
    ['liquidity_eligibility_binding', `${shock('liquidity_eligibility_pct')}<100,OR(${s('funding_need_pct_initial_gdp')}>0,${s('refinancing_need_pct_initial_gdp')}>0)`],
    ['sterilization_uptake_binding', `${s('uptake_absorption')}<${s('sterilization_requested_pct_initial_gdp')}`],
    ['sterilization_collateral_binding', `${s('sterilization_collateral_available_pct_initial_gdp')}<${s('uptake_absorption')}`],
    ['sterilization_reserve_binding', `${s('sterilization_applied_pct_initial_gdp')}<${s('sterilization_planned_pct_initial_gdp')}`],
  ]) put(key, `IF(AND(${condition}),1,0)`);
  put('sterilization_unfulfilled_pct_initial_gdp', `${s('sterilization_requested_pct_initial_gdp')}-${s('sterilization_applied_pct_initial_gdp')}`);
};
for (let q = 0; q <= 48; q++) {
  const col = column(q + 4), previous = column(q + 3), s = key => f(col, key), prev = key => f(previous, key);
  const put = (key, formula) => cell(economy, s(key), `=${formula}`, true);
  cell(economy, s('quarter_index'), q);
  if (q === 0) {
    for (const key of Object.keys(flattenState(source.initial_state)).filter(k => k !== 'quarter_index')) put(key, '0');
    for (const key of Object.keys(initialParameter)) put(key, initial(key));
    put('r_star_reference_pct', s('r_star_pct'));
    put('potential_output_index', p('initial_output_index'));
    put('actual_output_index', `IF(AND(${s('output_gap_pct')}>-100,${s('potential_output_index')}>0),${s('potential_output_index')}*(1+${s('output_gap_pct')}/100),NA())`);
    for (const key of ['potential_growth_pct', 'annualized_potential_growth_pct', 'annualized_actual_growth_pct']) put(key, p('initial_potential_growth_pct'));
    put('price_index', p('initial_price_index'));
    put('initial_annual_gdp_index', p('initial_output_index'));
    for (const key of initialFields) put(key, initial(key));
    // Keep this guard after initialFields so a scenario cannot overwrite it.
    put('policy_rate_pct', `IF(ISNUMBER(${p('initial_policy_rate_pct')}),${initial('policy_rate_pct')},NA())`);
    put('initial_asset_stock_pct_initial_gdp', s('asset_stock_pct_initial_gdp'));
    put('initial_actual_output_index', s('actual_output_index'));
    put('initial_price_index', s('price_index'));
    for (let i = 0; i < 120; i++) {
      put(arrayField(treasuryKey, i), `${s('asset_stock_pct_initial_gdp')}*'Assumptions'!$D$${sourceStart - 2}*'Assumptions'!$D$${sourceStart + i}`);
      put(arrayField(tagKey, i), '0');
    }
    for (let i = 0; i < 4; i++) put(arrayField(billKey, i), '0');
    put('mbs_stock_pct_initial_gdp', `${s('asset_stock_pct_initial_gdp')}*(1-'Assumptions'!$D$${sourceStart - 2})`);
    put('initial_duration_equivalent_pct_initial_gdp', `${cohortSum(s, treasuryKey, 120)}+${s('mbs_stock_pct_initial_gdp')}*(${p('mbs_duration_years')}/${p('treasury_duration_years')})`);
    put('duration_equivalent_pct_initial_gdp', s('initial_duration_equivalent_pct_initial_gdp'));
    put('initial_portfolio_premium_pct', s('term_premium_pct'));
    put('reserves_pct_initial_gdp', p('initial_reserves_pct_initial_gdp'));
    put('currency_pct_initial_gdp', p('initial_currency_pct_initial_gdp'));
    put('treasury_account_pct_initial_gdp', p('initial_treasury_account_pct_initial_gdp'));
    put('capital_other_pct_initial_gdp', `${s('asset_stock_pct_initial_gdp')}-${s('reserves_pct_initial_gdp')}-${s('currency_pct_initial_gdp')}-${s('treasury_account_pct_initial_gdp')}`);
    put('total_assets_pct_initial_gdp', s('asset_stock_pct_initial_gdp'));
    put('decision_nominal_gdp_ratio', '1'); put('ending_nominal_gdp_ratio', '1');
    put('reserve_buffer_pct_initial_gdp', p('reserve_buffer_pct_current_gdp')); put('reserve_clear_pct_initial_gdp', p('reserve_clear_pct_current_gdp'));
    put('sterilization_uptake_fraction', '1'); put('guidance_active', 'FALSE');
    put('last_policy_rate_request_pct', s('policy_rate_pct'));
    put('guidance_rate_pct', s('policy_rate_pct'));
    put('guidance_reference_inflation_pct', p('initial_inflation_rate_pct'));
    put('guidance_reference_output_gap_pct', p('initial_output_gap_pct'));
    put('guidance_followthrough_score', '1');
    put('credit_risk_wedge_pct', s('solvency_risk_wedge_pct'));
    put('credit_spread_pct', `${p('normal_credit_spread_pct')}+${s('credit_risk_wedge_pct')}`);
    for (let age = 0; age < 5; age++) put(`price_h${age}`, `${s('price_index')}/POWER(1+${s('annualized_quarterly_inflation_pct')}/100,${(4 - age) / 4})`);
    put('four_quarter_inflation_pct', `100*(${s('price_h4')}/${s('price_h0')}-1)`);
    writeRateConditions(s, s, put);
    put('initial_mbs_financing_rate_pct', `${s('long_yield_pct')}+${s('credit_spread_pct')}`);
    continue;
  }
  put('decision_nominal_gdp_ratio', `(${prev('actual_output_index')}/${prev('initial_actual_output_index')})*(${prev('price_index')}/${prev('initial_price_index')})`);
  const shock = key => `'Shocks'!${col}${shockRows.get(key)}`;
  const override = (row, fallback) => `IF(ISBLANK('Policy'!${col}${row}),${fallback},'Policy'!${col}${row})`;
  const requested = `CHOOSE('Policy Lab'!$C$6,${prev('r_star_pct')}+${prev('expected_short_inflation_pct')}+${p('policy_inflation_response')}*(${prev('four_quarter_inflation_pct')}-${p('inflation_target_pct')})+${p('policy_output_gap_response')}*${prev('output_gap_pct')},${prev('policy_rate_pct')})`;
  put('benchmark_rate', quote(requested));
  put('last_policy_rate_request_pct', override(6, s('benchmark_rate')));
  put('guidance_rate_pct', override(7, s('benchmark_rate')));
  put('guidance_inflation_sensitivity', override(8, p('policy_inflation_response')));
  put('guidance_output_gap_sensitivity', override(9, p('policy_output_gap_response')));
  put('asset_flow_request_pct_initial_gdp', `IF(ISNUMBER('Policy'!${col}10),'Policy'!${col}10*${s('decision_nominal_gdp_ratio')},NA())`);
  put('liquidity_request_pct_initial_gdp', `IF(ISNUMBER('Policy'!${col}11),'Policy'!${col}11*${s('decision_nominal_gdp_ratio')},NA())`);
  for (const [i, key] of ['reinvest_principal', 'maintain_ample_reserves', 'sterilize_purchases'].entries()) put(key, `IF(ISLOGICAL('Policy'!${col}${12 + i}),'Policy'!${col}${12 + i},NA())`);
  const controls = ['last_policy_rate_request_pct', 'guidance_rate_pct', 'guidance_inflation_sensitivity', 'guidance_output_gap_sensitivity', 'asset_flow_request_pct_initial_gdp', 'liquidity_request_pct_initial_gdp'];
  put('policy_valid', `AND(${controls.map(k => `ISNUMBER(${s(k)})`).join(',')},${onGrid(s('last_policy_rate_request_pct'))},${onGrid(s('guidance_rate_pct'))},ABS(${s('guidance_inflation_sensitivity')})<=${p('guidance_sensitivity_limit')},ABS(${s('guidance_output_gap_sensitivity')})<=${p('guidance_sensitivity_limit')},${s('liquidity_request_pct_initial_gdp')}>=0,${['reinvest_principal', 'maintain_ample_reserves', 'sterilize_purchases'].map(k => `ISLOGICAL(${s(k)})`).join(',')})`);
  put('policy_rate_pct', `IF(${s('policy_valid')},${s('last_policy_rate_request_pct')},NA())`);
  for (const key of ['initial_annual_gdp_index', 'initial_asset_stock_pct_initial_gdp', 'initial_actual_output_index', 'initial_price_index', 'initial_duration_equivalent_pct_initial_gdp', 'initial_portfolio_premium_pct', 'initial_mbs_financing_rate_pct', 'treasury_account_pct_initial_gdp', 'capital_other_pct_initial_gdp']) put(key, prev(key));
  writeBalance(s, prev, shock, put);
  put('solvency_risk_wedge_pct', `${prev('solvency_risk_wedge_pct')}*${p('solvency_risk_persistence')}+${shock('solvency_risk_innovation_pct')}`);
  put('credit_risk_wedge_pct', `${s('reserve_scarcity_wedge_pct')}+${s('local_access_wedge_pct')}+${s('solvency_risk_wedge_pct')}+${shock('credit_risk_innovation_pct')}`);
  put('credit_spread_pct', `${p('normal_credit_spread_pct')}+${s('credit_risk_wedge_pct')}`);
  const impliedPromise = `${prev('guidance_rate_pct')}+${prev('guidance_inflation_sensitivity')}*(${prev('four_quarter_inflation_pct')}-${prev('guidance_reference_inflation_pct')})+${prev('guidance_output_gap_sensitivity')}*(${prev('output_gap_pct')}-${prev('guidance_reference_output_gap_pct')})`;
  put('prior_commitment', `IF(${prev('guidance_active')},${quote(impliedPromise)},${s('policy_rate_pct')})`);
  put('guidance_followthrough_score', `IF(${prev('guidance_active')},EXP(-ABS(${s('policy_rate_pct')}-${s('prior_commitment')})/${p('credibility_followthrough_tolerance_pct')}),1)`);
  put('r_star_reference_pct', `${prev('r_star_reference_pct')}+${shock('r_star_reference_change_pct')}`);
  put('r_star_pct', `${s('r_star_reference_pct')}+${p('r_star_reversion_persistence')}*(${prev('r_star_pct')}-${prev('r_star_reference_pct')})+${shock('r_star_change_pct')}`);
  writeRateConditions(s, prev, put);
  put('financial_restraint_gap_pct', `${p('real_rate_gap_persistence')}*${prev('financial_restraint_gap_pct')}+(1-${p('real_rate_gap_persistence')})*${s('spot_financial_gap_pct')}`);
  put('potential_growth_pct', `IF(${shock('potential_growth_pct')}="unchanged",${prev('potential_growth_pct')},${shock('potential_growth_pct')})`);
  const structural = `${prev('structural_unemployment_pct')}+${shock('structural_unemployment_change_pct')}`;
  put('structural_unemployment_pct', `IF(AND(${structural}>0,${structural}<100),${structural},NA())`);
  put('potential_output_index', `${prev('potential_output_index')}*POWER(1+${s('potential_growth_pct')}/100,0.25)`);
  put('supply_pressure_pct', `${p('supply_pressure_persistence')}*${prev('supply_pressure_pct')}+${shock('supply_innovation_pct')}`);
  put('underlying_gap', `${p('output_gap_persistence')}*${prev('output_gap_pct')}-${p('real_rate_output_sensitivity')}*${s('financial_restraint_gap_pct')}+${shock('demand_shock_pct')}-${p('supply_output_gap_sensitivity')}*${s('supply_pressure_pct')}`);
  put('available_demand', `${prev('deferred_demand_pct')}*${prev('potential_output_index')}/${s('potential_output_index')}`);
  put('release_fraction', `(${p('demand_release_base_fraction')}+(${p('demand_release_max_fraction')}-${p('demand_release_base_fraction')})*ABS(${s('available_demand')})/(${p('demand_release_backlog_scale_pct')}+ABS(${s('available_demand')})))/(1+POWER(MAX(0,${s('financial_restraint_gap_pct')})/${p('demand_release_financing_scale_pct')},2))`);
  put('demand_release_pct', `${s('release_fraction')}*${s('available_demand')}`);
  put('output_gap_pct', `${s('underlying_gap')}+${s('demand_release_pct')}`);
  put('deferred_demand_pct', `(1-${p('demand_cancellation_fraction')})*${s('available_demand')}-${p('deferred_demand_share')}*${s('underlying_gap')}-${s('demand_release_pct')}`);
  const laborReference = s('structural_unemployment_pct'), laborGap = s('output_gap_pct'), laborSlope = p('unemployment_gap_sensitivity');
  const laborTarget = `IF(${laborGap}>=0,${laborReference}*EXP(-${laborSlope}*${laborGap}/${laborReference}),100-(100-${laborReference})*EXP(${laborSlope}*${laborGap}/(100-${laborReference})))`;
  put('unemployment_rate_pct', `${prev('unemployment_rate_pct')}+(1-${p('unemployment_gap_persistence')})*(${laborTarget}-${prev('unemployment_rate_pct')})`);
  put('inflation_pressure', `(${p('inflation_persistence')}*(1+${prev('annualized_quarterly_inflation_pct')}/100)+(1-${p('inflation_persistence')})*(1+${prev('expected_short_inflation_pct')}/100))*EXP((${p('inflation_output_gap_sensitivity')}*${prev('output_gap_pct')}+${p('inflation_supply_sensitivity')}*${s('supply_pressure_pct')})/(100+${p('inflation_target_pct')}))`);
  put('price_index', `${prev('price_index')}*POWER(${s('inflation_pressure')},0.25)`);
  for (let age = 0; age < 4; age++) put(`price_h${age}`, prev(`price_h${age + 1}`));
  put('price_h4', s('price_index'));
  put('four_quarter_inflation_pct', `100*(${s('price_h4')}/${s('price_h0')}-1)`);
  put('annualized_quarterly_inflation_pct', `100*(POWER(${s('price_index')}/${prev('price_index')},4)-1)`);
  put('short_anchor_weight', `${p('short_expectation_anchor_weight')}*${prev('credibility')}`);
  put('recent_expectation_base', `(1-${s('short_anchor_weight')})*(1+${prev('four_quarter_inflation_pct')}/100)+${s('short_anchor_weight')}*(1+${prev('expected_long_inflation_pct')}/100)`);
  put('expected_short_inflation_pct', `100*(((1-${p('short_expectation_recent_weight')})*(1+${prev('expected_short_inflation_pct')}/100)+${p('short_expectation_recent_weight')}*${s('recent_expectation_base')})*EXP(${p('short_expectation_supply_sensitivity')}*${s('supply_pressure_pct')}/(100+${p('inflation_target_pct')}))-1)`);
  put('long_anchor', `${prev('credibility')}*${p('inflation_target_pct')}+(1-${prev('credibility')})*${prev('four_quarter_inflation_pct')}`);
  put('expected_long_inflation_pct', `${prev('expected_long_inflation_pct')}+${p('long_expectation_adjustment')}*(${s('long_anchor')}-${prev('expected_long_inflation_pct')})`);
  put('inflation_miss_memory_pct', `${p('credibility_miss_persistence')}*${prev('inflation_miss_memory_pct')}+(1-${p('credibility_miss_persistence')})*ABS(${prev('four_quarter_inflation_pct')}-${p('inflation_target_pct')})`);
  put('inflation_performance', `EXP(-${s('inflation_miss_memory_pct')}/${p('credibility_miss_tolerance_pct')})`);
  put('credibility_score', `'Assumptions'!$D$${weightsRow}*${s('inflation_performance')}+'Assumptions'!$D$${weightsRow + 1}*${s('stance_adequacy_score')}+'Assumptions'!$D$${weightsRow + 2}*${s('guidance_followthrough_score')}`);
  put('credibility', clamp(`${prev('credibility')}+${p('credibility_adjustment')}*(${s('credibility_score')}-${prev('credibility')})`, 0, 1));
  put('current_hardship', `${p('public_inflation_burden_weight')}*ABS(${s('four_quarter_inflation_pct')}-${p('inflation_target_pct')})+${p('public_unemployment_burden_weight')}*MAX(0,${s('unemployment_rate_pct')}-${s('structural_unemployment_pct')})`);
  put('public_hardship_memory', `${p('public_hardship_memory_persistence')}*${prev('public_hardship_memory')}+(1-${p('public_hardship_memory_persistence')})*${s('current_hardship')}`);
  put('support_target', clamp(`${p('public_support_base')}-${s('current_hardship')}-${p('public_hardship_memory_weight')}*${s('public_hardship_memory')}`, 0, 100));
  put('public_support', `${prev('public_support')}+${p('public_support_adjustment')}*(${s('support_target')}-${prev('public_support')})`);
  put('actual_output_index', `IF(AND(${s('output_gap_pct')}>-100,${s('potential_output_index')}>0),${s('potential_output_index')}*(1+${s('output_gap_pct')}/100),NA())`);
  put('ending_nominal_gdp_ratio', `(${s('actual_output_index')}/${s('initial_actual_output_index')})*(${s('price_index')}/${s('initial_price_index')})`);
  put('annualized_actual_growth_pct', `100*(POWER(${s('actual_output_index')}/${prev('actual_output_index')},4)-1)`);
  put('annualized_potential_growth_pct', `100*(POWER(${s('potential_output_index')}/${prev('potential_output_index')},4)-1)`);
  put('guidance_active', 'TRUE');
  put('guidance_reference_inflation_pct', prev('four_quarter_inflation_pct'));
  put('guidance_reference_output_gap_pct', prev('output_gap_pct'));
}

for (const [key, row] of Object.entries(R)) cell(economy, `B${row}`, human(key));
economy.getRange(`B100:AZ${nextModelRow - 1}`).format = { font: { name: 'Arial', size: 10, color: C.ink }, rowHeight: 22, verticalAlignment: 'center' };
economy.getRange(`B100:B${nextModelRow - 1}`).format.columnWidth = 54;
economy.getRange(`D100:AZ${nextModelRow - 1}`).setNumberFormat('0.000');
for (let q = 0; q <= 48; q++) {
  const col = column(q + 4);
  for (const [label, key] of [['securities', 'asset_stock_pct_initial_gdp'], ['reserves', 'reserves_pct_initial_gdp'], ['loans', 'outstanding_liquidity_pct_initial_gdp'], ['rrp', 'reverse_repo_pct_initial_gdp']]) cell(economy, f(col, `ending_${label}_pct_current_gdp`), `=${f(col, key)}/${f(col, 'ending_nominal_gdp_ratio')}`, true);
}
await fs.writeFile(new URL('workbook-model-map.json', evidence), JSON.stringify(R, null, 2));

// Player controls remain separate from the one calculation chain.
for (const sheet of [policy, shocks]) {
  sheet.getRange('E4:AZ4').values = [Array.from({ length: 48 }, (_, q) => q + 1)]; headers(sheet, 'B4:AZ4');
  cell(sheet, 'B4', 'Decision quarter');
}
for (const [row, label] of [[6, 'Rate request (%)'], [7, 'Next-quarter guidance (%)'], [8, 'Guidance: inflation response'], [9, 'Guidance: output-gap response'], [10, 'Purchases / runoff cap (% current GDP)'], [11, 'Liquidity offer (% current GDP)'], [12, 'Reinvest principal'], [13, 'Maintain ample reserves'], [14, 'Sterilize purchases']]) {
  cell(policy, `B${row}`, label); input(policy, `E${row}:AZ${row}`);
  if (row >= 10) policy.getRange(`E${row}:AZ${row}`).values = [[row < 12 ? 0 : row !== 14]];
}
cell(policy, 'B16', 'Blanks in6–9 use the benchmark; zero is explicit. Rate/guidance grid:1bp.');
cell(policy, 'B17', 'Modes require TRUE/FALSE. Negative purchases cap actual principal runoff.');
cell(policy, 'B18', 'Offers and flows: current meeting GDP; ending stocks: ending GDP.');
const endingStocks = new Set(['outstanding_liquidity_pct_initial_gdp', 'asset_stock_pct_initial_gdp', 'reserves_pct_initial_gdp', 'reverse_repo_pct_initial_gdp', 'total_assets_pct_initial_gdp']);
const policyOutputs = ['policy_rate_pct', 'prior_commitment', 'guidance_followthrough_score', 'asset_flow_applied_pct_initial_gdp', 'liquidity_applied_pct_initial_gdp', 'outstanding_liquidity_pct_initial_gdp', 'credit_spread_pct', 'four_quarter_inflation_pct', 'unemployment_rate_pct', 'public_support', 'principal_due_pct_initial_gdp', 'principal_runoff_pct_initial_gdp', 'principal_reinvestment_pct_initial_gdp', 'long_securities_runoff_pct_initial_gdp', 'reserve_maintenance_purchase_pct_initial_gdp', 'sterilization_applied_pct_initial_gdp', 'sterilization_unfulfilled_pct_initial_gdp', 'reserves_pct_initial_gdp', 'reverse_repo_pct_initial_gdp', 'total_assets_pct_initial_gdp'];
for (const [i, key] of policyOutputs.entries()) {
  const row = 20 + i; cell(policy, `B${row}`, human(key).replace('initial GDP', 'current GDP'));
  policy.getRange(`E${row}:AZ${row}`).formulas = [Array.from({ length: 48 }, (_, q) => {
    const col = column(q + 5), denominator = endingStocks.has(key) ? 'ending_nominal_gdp_ratio' : 'decision_nominal_gdp_ratio';
    return `='Economy'!${col}${R[key]}${key.endsWith('_pct_initial_gdp') ? `/'Economy'!${col}${R[denominator]}` : ''}`;
  })];
}
policy.getRange('E6:AZ11').setNumberFormat('0.00');
policy.getRange('E20:AZ39').setNumberFormat('0.00');

// Compact output table and editable native charts, with a single linked plot table.
lab.getRange('B11:D11').values = [['At selected quarter', 'Value', 'Unit']]; headers(lab, 'B11:D11');
const metrics = [['four_quarter_inflation_pct', 'Inflation, four quarters', '%'], ['unemployment_rate_pct', 'Unemployment', '%'], ['output_gap_pct', 'Output gap', '% potential'], ['policy_rate_pct', 'Policy rate', '%'], ['credibility', 'Monetary credibility', '0–1 score'], ['public_support', 'Public support', '0–100 score']];
for (const [i, [key, label, unit]] of metrics.entries()) {
  cell(lab, `B${12 + i}`, label); cell(lab, `C${12 + i}`, `=INDEX('Economy'!$D$${R[key]}:$AZ$${R[key]},1,$C$5+1)`, true); cell(lab, `D${12 + i}`, unit);
}
lab.getRange('C12:C17').setNumberFormat('0.00');
cell(lab, 'F12', 'Use Policy to test a different decision at any quarter.');
cell(lab, 'F14', 'Future shocks are visible here for audit; the game conceals them.');
cell(lab, 'F16', 'Lower inflation can cost output and jobs. Liquidity does not repair solvency.');
const plotKeys = ['four_quarter_inflation_pct', 'expected_short_inflation_pct', 'expected_long_inflation_pct', 'unemployment_rate_pct', 'structural_unemployment_pct', 'policy_rate_pct', 'long_yield_pct', 'public_support', 'credibility'];
lab.getRange('B57:K57').values = [['Quarter', 'Inflation', 'Short expectations', 'Long expectations', 'Unemployment', 'Structural reference', 'Policy rate', 'Long yield', 'Public support', 'Credibility × 100']];
headers(lab, 'B57:K57');
for (let q = 0; q <= 48; q++) {
  const row = q + 58, col = column(q + 4);
  cell(lab, `B${row}`, `Q${q}`);
  lab.getRange(`C${row}:K${row}`).formulas = [plotKeys.map(key => `='Economy'!${col}${R[key]}${key === 'credibility' ? '*100' : ''}`)];
}
const chart = (title, columns, start, end, colors) => {
  const ranges = [lab.getRange('B57:B106'), ...columns.map(c => lab.getRange(`${c}57:${c}106`))];
  const plot = lab.charts.add('line', ranges); plot.title = title; plot.setPosition(start, end);
  plot.titleTextStyle.fontSize = 12; plot.titleTextStyle.typeface = 'Arial';
  plot.legend = { position: 'top', textStyle: { typeface: 'Arial', fontSize: 10 } };
  plot.xAxis = { axisType: 'textAxis', textStyle: { typeface: 'Arial', fontSize: 9 }, tickLabelInterval: 8 };
  plot.yAxis = { numberFormatCode: '0.00', numberFormatSourceLinked: false, textStyle: { typeface: 'Arial', fontSize: 10 } };
  plot.series.items.forEach((series, i) => { series.line = { fill: colors[i], style: i === 1 ? 'dashed' : 'solid', width: 2 }; });
};
chart('Inflation and expectations (%)', ['C', 'D', 'E'], 'B20', 'H35', [C.copper, C.blue, C.green]);
chart('Unemployment (%)', ['F', 'G'], 'I20', 'P35', [C.blue, C.muted]);
chart('Policy and long yield (%)', ['H', 'I'], 'B37', 'H52', [C.navy, C.copper]);
chart('Model confidence scores (0–100)', ['J', 'K'], 'I37', 'P52', [C.green, C.copper]);
cell(lab, 'B54', 'Public support has no automatic loss gate. A finite valid path can continue through the laboratory horizon.');
lab.getRange('E1:P106').format.columnWidth = 12;
lab.getRange('C58:K106').setNumberFormat('0.00');

workbook.recalculate();
const checks = [];
const verifyTrace = (label, states) => {
  let worst = 0;
  for (const [q, state] of states.entries()) {
    const col = column(q + 4);
    for (const [key, expected] of Object.entries(flattenState(state))) {
      assert.ok(R[key], `State field missing from workbook: ${key}`);
      const actual = economy.getRange(`${col}${R[key]}`).values[0][0];
      if (typeof expected === 'boolean') assert.equal(typeof actual, 'boolean', `${label} q${q} boolean type: ${key}`);
      const error = Math.abs(Number(actual) - Number(expected)); worst = Math.max(worst, error);
      assert.ok(Number.isFinite(Number(actual)) && error < 1e-7, `${label} q${q} ${key}: workbook ${actual}, Godot ${expected}`);
    }
  }
  return worst;
};
for (let caseIndex = 0; caseIndex < cases.length; caseIndex++) {
  cell(lab, 'C4', caseIndex + 1); workbook.recalculate();
  checks.push({ case: ids[caseIndex], quarters: 48, maxAbsoluteError: verifyTrace(ids[caseIndex], [cases[caseIndex].initial_state, ...cases[caseIndex].quarters.map(x => x.state)]) });
}
cell(lab, 'C4', 3); workbook.recalculate();
assert.ok(Math.abs(economy.getRange('D6').values[0][0] - cases[2].initial_state.actual_output_index) < 1e-7, 'Initial actual output must match the canonical level-accounting identity');
console.log('PARITY', JSON.stringify(checks));
cell(policy, 'E6', 0); workbook.recalculate();
assert.equal(economy.getRange('E20').values[0][0], 0, 'An explicit zero rate request applies in full without a ramp cap');
assert.ok(Math.abs(economy.getRange('E43').values[0][0] - 3.5) < 1e-7, 'Blank guidance follows its benchmark independently of a rate override');
cell(policy, 'E6', null); workbook.recalculate();
const variants = JSON.parse(await fs.readFile(new URL('./reference-v1/policy-variants.json', import.meta.url), 'utf8'));
for (const variant of variants) {
  cell(lab, 'C4', ids.indexOf(variant.case) + 1);
  const previous = policy.getRange(variant.cell).values[0][0];
  cell(policy, variant.cell, nominalKeys.has(variant.control) ? variant.value / nominalRatio(variant.states[variant.quarter]) : variant.value); workbook.recalculate();
  checks.push({ policyEdit: variant.name, maxAbsoluteError: verifyTrace(variant.name, variant.states) });
  cell(policy, variant.cell, previous);
}
// Real Godot boundary states use this same editable chain, not a second calculation.
const priceBoundaries = JSON.parse(await fs.readFile(new URL('./reference-v1/price-boundaries.json', import.meta.url), 'utf8'));
cell(lab, 'C4', 1); cell(lab, 'C6', 2);
for (const fixture of priceBoundaries) {
  const initialEdits = Object.keys(fixture.initial).map(key => [`D${initialRows.get(key) + 1}`, fixture.initial[key]]);
  const shockEdits = shockKeys.map(key => [`E${shockRows.get(key) + 1}`, fixture.shocks[0][key] ?? shockDefault(key)]);
  const saved = [...initialEdits, ...shockEdits].map(([ref, value], index) => {
    const sheet = index < initialEdits.length ? assumptions : shocks;
    const previous = sheet.getRange(ref).values[0][0];
    const formula = sheet.getRange(ref).formulas[0][0];
    cell(sheet, ref, value);
    return [sheet, ref, previous, formula];
  });
  workbook.recalculate();
  checks.push({ priceBoundary: fixture.name, maxAbsoluteError: verifyTrace(fixture.name, fixture.states) });
  for (const [sheet, ref, value, formula] of saved) {
    cell(sheet, ref, formula || value, Boolean(formula));
    assert.equal(sheet.getRange(ref)[formula ? 'formulas' : 'values'][0][0], formula || value, 'Boundary fixture restores its exact input');
  }
}
for (const key of ['annualized_quarterly_inflation_pct', 'expected_short_inflation_pct', 'expected_long_inflation_pct']) {
  const parameter = `C${parameterRow.get(initialParameter[key])}`, sourceCell = `D${initialRows.get(key) + 1}`;
  for (const [ref, formula] of [[parameter, null], [sourceCell, assumptions.getRange(sourceCell).formulas[0][0]]]) {
    const previous = assumptions.getRange(ref).values[0][0];
    cell(assumptions, ref, -100); workbook.recalculate();
    assert.equal(economy.getRange(`D${R[key]}`).values[0][0], '#N/A', 'Nonpositive gross initial inflation or expectations are rejected');
    cell(assumptions, ref, formula || previous, Boolean(formula));
  }
}
cell(lab, 'C6', 1); cell(lab, 'C4', 3); workbook.recalculate();
assert.ok(verifyTrace('restored price boundaries', [cases[2].initial_state, ...cases[2].quarters.map(x => x.state)]) < 1e-7);
console.log('PASS: three native price boundaries, strict gross-rate inputs and restored model parity');
// Missing unselected input must not break the chosen case; selected missing input must not become zero.
const supplyRow = shockRows.get('supply_innovation_pct');
const supplyCell = `E${supplyRow + 3}`, supplyValue = shocks.getRange(supplyCell).values[0][0];
cell(lab, 'C4', 1); cell(shocks, supplyCell, null); workbook.recalculate();
assert.ok(Number.isFinite(economy.getRange('AZ13').values[0][0]), 'Missing unselected shock is isolated');
cell(lab, 'C4', 3); workbook.recalculate();
assert.equal(shocks.getRange(`E${supplyRow}`).values[0][0], '#N/A', 'Selected missing shock remains unavailable');
cell(shocks, supplyCell, supplyValue); workbook.recalculate();
const fundingRow = shockRows.get('funding_need_pct_initial_gdp');
const fundingCell = `E${fundingRow + 3}`, fundingValue = shocks.getRange(fundingCell).values[0][0];
cell(shocks, fundingCell, -1); workbook.recalculate();
assert.equal(shocks.getRange(`E${fundingRow}`).values[0][0], '#N/A', 'Negative funding need is rejected');
cell(shocks, fundingCell, fundingValue); workbook.recalculate();
const later = `${column(36)}${supplyRow + 3}`, laterValue = shocks.getRange(later).values[0][0];
const inflationBefore = economy.getRange('AJ12').values[0][0], outputBefore = economy.getRange('AI6').values[0][0];
cell(shocks, later, laterValue + 0.5); workbook.recalculate();
assert.ok(economy.getRange('AJ12').values[0][0] > inflationBefore, 'A later-period supply edit updates that period');
assert.equal(economy.getRange('AI6').values[0][0], outputBefore, 'A later-period shock cannot change earlier output');
cell(shocks, later, laterValue); workbook.recalculate();
assert.ok(verifyTrace('restored supply case', [cases[2].initial_state, ...cases[2].quarters.map(x => x.state)]) < 1e-7);
const laborInput = `D${initialRows.get('unemployment_rate_pct') + 6}`, laborValue = assumptions.getRange(laborInput).values[0][0];
cell(lab, 'C4', 6);
for (const endpoint of [0, 100]) {
  cell(assumptions, laborInput, endpoint); workbook.recalculate();
  assert.equal(economy.getRange('D16').values[0][0], endpoint, 'Physical initial unemployment endpoint is preserved');
  const adjusted = economy.getRange('E16').values[0][0];
  assert.ok(Number.isFinite(adjusted) && adjusted >= 0 && adjusted <= 100, 'Labor endpoint adjusts within physical bounds');
}
cell(assumptions, laborInput, 100.01); workbook.recalculate();
assert.equal(economy.getRange('D16').values[0][0], '#N/A', 'Nonphysical initial unemployment stays unavailable');
cell(assumptions, laborInput, laborValue); cell(lab, 'C4', 3);
const referenceInput = `C${parameterRow.get('initial_structural_unemployment_pct')}`, referenceValue = assumptions.getRange(referenceInput).values[0][0];
const referenceShock = `E${shockRows.get('structural_unemployment_change_pct') + 3}`, referenceShockValue = shocks.getRange(referenceShock).values[0][0];
for (const [reference, shift] of [[0.25, -0.5], [99.75, 0.5]]) {
  cell(assumptions, referenceInput, reference); cell(shocks, referenceShock, shift); workbook.recalculate();
  assert.equal(economy.getRange('E17').values[0][0], '#N/A', 'Nonphysical structural shift stays unavailable');
  assert.equal(economy.getRange('E16').values[0][0], '#N/A', 'Invalid labor reference cannot produce a healthy rate');
}
cell(assumptions, referenceInput, referenceValue); cell(shocks, referenceShock, referenceShockValue); workbook.recalculate();
assert.ok(verifyTrace('restored labor boundaries', [cases[2].initial_state, ...cases[2].quarters.map(x => x.state)]) < 1e-7);
console.log('PASS: labor endpoints, invalid reference shifts and restored model parity');
// Recovery controls share the engine's domains and remain auditable after edits.
for (const [key, value, affected] of [
  ['deferred_demand_share', 1.1, 'deferred_demand_pct'],
  ['demand_release_base_fraction', 0.3, 'demand_release_pct'],
  ['demand_cancellation_fraction', 0.9, 'demand_release_pct'],
  ['demand_release_backlog_scale_pct', 0, 'demand_release_pct'],
  ['demand_release_financing_scale_pct', 0, 'demand_release_pct'],
  ['short_expectation_anchor_weight', 1.1, 'expected_short_inflation_pct'],
  ['r_star_reversion_persistence', 1.1, 'r_star_pct'],
]) {
  const address = `C${parameterRow.get(key)}`, prior = assumptions.getRange(address).values[0][0];
  cell(assumptions, address, value); workbook.recalculate();
  assert.equal(economy.getRange(`E${R[affected]}`).values[0][0], '#N/A', `Invalid recovery assumption stays unavailable: ${key}`);
  cell(assumptions, address, prior);
}
const structuralRateInput = `E${shockRows.get('r_star_reference_change_pct') + 3}`;
const structuralRatePrior = shocks.getRange(structuralRateInput).values[0][0];
cell(shocks, structuralRateInput, 0.5); workbook.recalculate();
assert.equal(economy.getRange(`E${R.r_star_reference_pct}`).values[0][0], 2, 'Permanent neutral-rate shift changes its separate centre');
assert.equal(economy.getRange(`F${R.r_star_reference_pct}`).values[0][0], 2, 'Permanent centre is not erased next quarter');
cell(shocks, structuralRateInput, structuralRatePrior); workbook.recalculate();
assert.ok(verifyTrace('restored recovery inputs', [cases[2].initial_state, ...cases[2].quarters.map(x => x.state)]) < 1e-7);
console.log('PASS: recovery domains, permanent structural reference and restored full parity');

const rateBoundaries = JSON.parse(await fs.readFile(new URL('./reference-v1/rate-boundaries.json', import.meta.url), 'utf8'));
cell(lab, 'C4', 1); cell(lab, 'C6', 2);
const policyRows = { policy_rate_request_pct: 6, guidance_rate_pct: 7, guidance_inflation_sensitivity: 8,
  guidance_output_gap_sensitivity: 9, asset_flow_request_pct_initial_gdp: 10, liquidity_request_pct_initial_gdp: 11, reinvest_principal: 12, maintain_ample_reserves: 13, sterilize_purchases: 14 };
const balanceBoundaries = JSON.parse(await fs.readFile(new URL('./reference-v1/balance-boundaries.json', import.meta.url), 'utf8'));
for (const [kind, fixtures] of [['rateBoundary', rateBoundaries], ['balanceBoundary', balanceBoundaries]]) for (const fixture of fixtures) {
  const edits = [
    ...Object.entries(fixture.initial).map(([key, value]) => [assumptions, `D${initialRows.get(key) + 1}`, value]),
    ...Object.entries(fixture.parameter_overrides ?? {}).map(([key, value]) => [assumptions, `C${parameterRow.get(key)}`, value]),
    ...fixture.shocks.flatMap((shock, q) => shockKeys.map(key => [shocks, `${column(q + 5)}${shockRows.get(key) + 1}`, shock[key] ?? shockDefault(key)])),
    ...fixture.policies.flatMap((decision, q) => Object.entries(decision).map(([key, value]) => [policy, `${column(q + 5)}${policyRows[key]}`, nominalKeys.has(key) ? value / nominalRatio(fixture.states[q]) : value])),
  ];
  const saved = edits.map(([sheet, ref, value]) => {
    assert.ok(!ref.includes('NaN') && !ref.includes('undefined'), `Unmapped boundary input ${ref}`);
    const previous = sheet.getRange(ref).values[0][0], formula = sheet.getRange(ref).formulas[0][0];
    cell(sheet, ref, value);
    return [sheet, ref, previous, formula];
  });
  workbook.recalculate();
  checks.push({ [kind]: fixture.name, maxAbsoluteError: verifyTrace(fixture.name, fixture.states) });
  console.log(`PASS: ${kind} ${fixture.name}`);
  for (const [sheet, ref, value, formula] of saved) cell(sheet, ref, formula || value, Boolean(formula));
}
for (const raw of [-3.505, 3.505]) {
  cell(policy, 'E6', `=${quote(raw)}`, true); workbook.recalculate();
  assert.ok(Math.abs(economy.getRange('E20').values[0][0] - Math.sign(raw) * 3.51) < 1e-8, 'Half-step nominal quotes round symmetrically away from zero');
}
cell(policy, 'E6', null); cell(lab, 'C6', 1); cell(lab, 'C4', 3);
for (const address of ['E6', 'E7']) {
  for (const value of [-1.001, 3.501, 'invalid']) {
    cell(policy, address, value); workbook.recalculate();
    assert.equal(economy.getRange('E20').values[0][0], '#N/A', 'Off-grid and nonnumeric nominal quotes stay unavailable');
  }
  cell(policy, address, null);
}
const initialRate = `D${initialRows.get('policy_rate_pct') + 3}`, initialRateFormula = assumptions.getRange(initialRate).formulas[0][0], initialRateValue = assumptions.getRange(initialRate).values[0][0];
cell(assumptions, initialRate, 3.501); workbook.recalculate();
assert.equal(economy.getRange('D20').values[0][0], '#N/A', 'Initial nominal quote uses the same grid');
cell(assumptions, initialRate, initialRateFormula || initialRateValue, Boolean(initialRateFormula));
const initialRateParameter = `C${parameterRow.get('initial_policy_rate_pct')}`, initialRateParameterValue = assumptions.getRange(initialRateParameter).values[0][0];
cell(lab, 'C4', 6); cell(assumptions, initialRateParameter, 3.501); workbook.recalculate();
assert.equal(economy.getRange('D20').values[0][0], '#N/A', 'A scenario override cannot conceal an invalid initial-rate parameter');
cell(assumptions, initialRateParameter, initialRateParameterValue); cell(lab, 'C4', 3);
for (const [key, value, affected] of [['minimum_rate_increment_pct', 0, 'policy_rate_pct'], ['minimum_rate_increment_pct', -0.01, 'policy_rate_pct'], ['negative_rate_efficacy_scale_pct', 0, 'effective_policy_rate_pct']]) {
  const address = `C${parameterRow.get(key)}`, previous = assumptions.getRange(address).values[0][0];
  cell(assumptions, address, value); workbook.recalculate();
  assert.equal(economy.getRange(`E${R[affected]}`).values[0][0], '#N/A', `Nonpositive rate assumption stays unavailable: ${key}`);
  cell(assumptions, address, previous);
}
workbook.recalculate();
assert.ok(verifyTrace('restored signed-rate boundaries', [cases[2].initial_state, ...cases[2].quarters.map(x => x.state)]) < 1e-7);
console.log('PASS: seven native signed-rate boundaries, quote grid, conditional delivery and restored full parity');

console.log('PASS: four policy edits, blank/zero distinction, missing-case isolation, invalid funding and later-period causality');
await fs.writeFile(new URL('workbook-parity.json', evidence), JSON.stringify(checks, null, 2));
console.log((await workbook.inspect({ kind: 'table', range: 'Policy Lab!B11:D17', include: 'values,formulas', tableMaxRows: 8, tableMaxCols: 4 })).ndjson);
console.log((await workbook.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!', options: { useRegex: true, maxResults: 20 }, summary: 'Formula error scan' })).ndjson);
await fs.mkdir(out, { recursive: true });
const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(fileURLToPath(new URL('Federal Reserve Policy Lab.xlsx', out)));
for (const [sheetName, range, file] of [['Policy Lab', 'A1:P55', 'lab'], ['Policy', 'A1:M40', 'policy'], ['Assumptions', 'A1:J18', 'assumptions'], ['Economy', 'A1:L23', 'economy'], ['Shocks', 'A1:L22', 'shocks'], ['Assumptions', `B${source.parameters.length - 2}:H${weightsRow + 2}`, 'recovery-assumptions'], ['Economy', 'B77:L93', 'recovery-rate-equations'], ['Assumptions', `B${parameterRow.get('minimum_rate_increment_pct')}:H${parameterRow.get('negative_rate_efficacy_scale_pct')}`, 'rate-assumptions'], ['Assumptions', `B${sourceStart - 4}:F${sourceStart + 14}`, 'portfolio-ladder'], ['Assumptions', `B${sourceStart + 105}:F${sourceStart + 119}`, 'portfolio-ladder-tail']]) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: 'png' });
  await fs.writeFile(new URL(`workbook-${file}.png`, evidence), new Uint8Array(await preview.arrayBuffer()));
}
cell(lab, 'C4', 7); workbook.recalculate();
for (const [sheetName, range, file] of [['Policy Lab', 'A1:P55', 'curated-lab'], ['Shocks', 'A1:Z22', 'curated-shocks'], ['Shocks', `A${shockNoteRow}:P${shockNoteRow + 3}`, 'campaign-note']]) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: 'png' });
  await fs.writeFile(new URL(`workbook-${file}.png`, evidence), new Uint8Array(await preview.arrayBuffer()));
}
cell(lab, 'C4', 3); workbook.recalculate();
console.log('EXPORTED Federal Reserve Policy Lab.xlsx');
