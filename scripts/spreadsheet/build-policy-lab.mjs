import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const ids = ['base', 'demand_boom', 'supply_shock', 'funding_stress', 'unanchored_inflation', 'lower_bound_slump', 'mixed_crises'];
const cases = await Promise.all(ids.map(async id => JSON.parse(await fs.readFile(new URL(`./reference-v1/${id}.json`, import.meta.url), 'utf8'))));
const source = cases[0];
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
const parameterRow = new Map();
const shares = /persistence|adjustment|fraction|_weight$/;
const unboundedWeights = new Set(['public_inflation_burden_weight', 'public_unemployment_burden_weight', 'public_hardship_memory_weight']);
for (let i = 0; i < source.parameters.length; i++) {
  const record = source.parameters[i], row = i + 6, ref = `C${row}`;
  parameterRow.set(record.key, row);
  cell(assumptions, `B${row}`, human(record.key)); cell(assumptions, ref, record.value);
  let domain = `ISNUMBER(${ref})`;
  if (record.classification === 'mathematical_identity' || record.key === 'inflation_target_pct') domain = `AND(${domain},${ref}=${record.value})`;
  else if ((shares.test(record.key) && !unboundedWeights.has(record.key)) || record.key === 'initial_credibility') domain = `AND(${domain},${ref}>=0,${ref}<=1)`;
  else if (record.key.includes('public_support')) domain = `AND(${domain},${ref}>=0,${ref}<=100)`;
  else if (record.key === 'initial_structural_unemployment_pct') domain = `AND(${domain},${ref}>0,${ref}<100)`;
  else if (record.key === 'initial_unemployment_pct') domain = `AND(${domain},${ref}>=0,${ref}<=100)`;
  else if (['initial_inflation_rate_pct', 'initial_expected_short_inflation_pct', 'initial_expected_long_inflation_pct'].includes(record.key)) domain = `AND(${domain},${ref}>-100)`;
  else if (/tolerance|stance_scale|initial_output_index|initial_price_index/.test(record.key)) domain = `AND(${domain},${ref}>0)`;
  else if (/sensitivity|limit|capacity|normal_credit|burden_weight|hardship_memory_weight/.test(record.key)) domain = `AND(${domain},${ref}>=0)`;
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
assumptions.getRange('B6:J65').format.wrapText = true;
assumptions.getRange('B6:J65').format.rowHeight = 48;
const p = key => { assert.ok(parameterRow.has(key), `Unknown parameter ${key}`); return `'Assumptions'!$D$${parameterRow.get(key)}`; };
cell(assumptions, 'B68', 'Credibility weights (fixed in core)');
for (const [i, label, value] of [[0, 'Inflation performance', 0.4], [1, 'Stance adequacy', 0.4], [2, 'Conditional follow-through', 0.2]]) {
  cell(assumptions, `B${69 + i}`, label); cell(assumptions, `D${69 + i}`, value);
}
cell(assumptions, 'H69', 'The 40/40/20 rule is a game-design assumption, not an estimated Federal Reserve objective.');
cell(assumptions, 'H71', 'Public support is a fictional score with gradual recovery, not a legal dismissal threshold.');

const initialParameter = {
  output_gap_pct: 'initial_output_gap_pct', annualized_quarterly_inflation_pct: 'initial_inflation_rate_pct',
  expected_short_inflation_pct: 'initial_expected_short_inflation_pct', expected_long_inflation_pct: 'initial_expected_long_inflation_pct',
  policy_rate_pct: 'initial_policy_rate_pct', unemployment_rate_pct: 'initial_unemployment_pct', credibility: 'initial_credibility',
  public_support: 'initial_public_support', r_star_pct: 'initial_r_star_pct', structural_unemployment_pct: 'initial_structural_unemployment_pct',
  asset_stock_pct_initial_gdp: 'initial_asset_stock_pct_initial_gdp', term_premium_pct: 'initial_term_premium_pct',
};
const initialRows = new Map();
const initialFields = [...new Set(cases.flatMap(x => Object.keys(x.scenario.initial)))];
const caseStride = cases.length + 2;
let initialRow = 77;
for (const key of initialFields) {
  assert.ok(initialParameter[key], `Undocumented initial case driver ${key}`);
  initialRows.set(key, initialRow);
  cell(assumptions, `B${initialRow}`, `${human(key)}: active`);
  const choices = cases.map((_, i) => `D${initialRow + i + 1}`).join(',');
  const present = cases.map((_, i) => `ISNUMBER(D${initialRow + i + 1})`).join(',');
  const selected = `CHOOSE('Policy Lab'!$C$4,${choices})`;
  const numeric = `CHOOSE('Policy Lab'!$C$4,${present})`;
  const valid = key === 'unemployment_rate_pct' ? `AND(${numeric},${selected}>=0,${selected}<=100)`
    : ['annualized_quarterly_inflation_pct', 'expected_short_inflation_pct', 'expected_long_inflation_pct'].includes(key) ? `AND(${numeric},${selected}>-100)` : numeric;
  cell(assumptions, `D${initialRow}`, `=IF(${valid},${selected},NA())`, true);
  assumptions.getRange(`B${initialRow}:F${initialRow}`).format.fill = C.pale;
  for (let i = 0; i < cases.length; i++) {
    const row = initialRow + i + 1, value = cases[i].scenario.initial[key];
    cell(assumptions, `B${row}`, cases[i].scenario.label);
    if (value === undefined) cell(assumptions, `D${row}`, `=${p(initialParameter[key])}`, true);
    else { cell(assumptions, `D${row}`, value); input(assumptions, `D${row}`); }
  }
  initialRow += caseStride;
}
const initial = key => initialRows.has(key) ? `'Assumptions'!$D$${initialRows.get(key)}` : initialParameter[key] ? p(initialParameter[key]) : '0';

const shockKeys = ['demand_shock_pct', 'supply_innovation_pct', 'potential_growth_pct', 'r_star_change_pct', 'structural_unemployment_change_pct', 'funding_need_pct_initial_gdp', 'eligible_collateral_pct_initial_gdp', 'collateral_haircut_pct', 'liquidity_eligibility_pct', 'credit_risk_innovation_pct', 'solvency_risk_innovation_pct'];
const shockRows = new Map();
for (let i = 0; i < shockKeys.length; i++) {
  const key = shockKeys[i], row = 6 + i * caseStride;
  shockRows.set(key, row);
  cell(shocks, `B${row}`, `${human(key)}: active`);
  shocks.getRange(`B${row}:AZ${row}`).format.fill = C.pale;
  for (let n = 0; n < cases.length; n++) {
    cell(shocks, `B${row + n + 1}`, cases[n].scenario.label);
    shocks.getRange(`E${row + n + 1}:AZ${row + n + 1}`).values = [cases[n].shock_path.map(x => x[key] ?? (key === 'potential_growth_pct' ? null : 0))];
    input(shocks, `E${row + n + 1}:AZ${row + n + 1}`);
  }
  const formulas = Array.from({ length: 48 }, (_, q) => {
    const col = column(q + 5), refs = cases.map((_, n) => `${col}${row + n + 1}`);
    const choose = values => `CHOOSE('Policy Lab'!$C$4,${values.join(',')})`;
    const limit = { demand_shock_pct: 10, supply_innovation_pct: 5, potential_growth_pct: 20, r_star_change_pct: 1, structural_unemployment_change_pct: 0.5, credit_risk_innovation_pct: 5, solvency_risk_innovation_pct: 5 }[key] ?? 100;
    const signed = ['demand_shock_pct', 'supply_innovation_pct', 'potential_growth_pct', 'r_star_change_pct', 'structural_unemployment_change_pct'].includes(key);
    const valid = choose(refs.map(ref => `AND(ISNUMBER(${ref}),${ref}>=${signed ? -limit : 0},${ref}<=${limit})`));
    const numeric = `IF(${valid},${choose(refs)},NA())`;
    return `=${key === 'potential_growth_pct' ? `IF(${choose(refs.map(ref => `ISBLANK(${ref})`))},"unchanged",${numeric})` : numeric}`;
  });
  shocks.getRange(`E${row}:AZ${row}`).formulas = [formulas];
}
const shockNoteRow = 6 + shockKeys.length * caseStride;
cell(shocks, `B${shockNoteRow}`, 'Seed 1 realized paths from Godot 4.7.2. Hypothetical disturbances; no historical calibration.');
cell(shocks, `B${shockNoteRow + 1}`, 'Blank potential growth keeps the previous trend. All other active shock inputs must be numeric.');
cell(shocks, `B${shockNoteRow + 2}`, 'Recurring crises: paired episodes every 12 to 20 quarters at 0.75 to 1.25 times the demand, supply or funding template.');
shocks.getRange(`E6:AZ${shockNoteRow - 2}`).setNumberFormat('0.000');

const R = {
  quarter_index: 4, potential_output_index: 5, actual_output_index: 6, annualized_actual_growth_pct: 7,
  annualized_potential_growth_pct: 8, output_gap_pct: 9, potential_growth_pct: 10, price_index: 11,
  annualized_quarterly_inflation_pct: 12, four_quarter_inflation_pct: 13, expected_short_inflation_pct: 14,
  expected_long_inflation_pct: 15, unemployment_rate_pct: 16, structural_unemployment_pct: 17, r_star_pct: 18,
  last_policy_rate_request_pct: 19, policy_rate_pct: 20, long_yield_pct: 21, financial_restraint_gap_pct: 22,
  asset_flow_request_pct_initial_gdp: 23, asset_flow_applied_pct_initial_gdp: 24, asset_stock_pct_initial_gdp: 25,
  initial_asset_stock_pct_initial_gdp: 26, asset_stock_capacity_pct_initial_gdp: 27, term_premium_pct: 28,
  funding_need_pct_initial_gdp: 29, eligible_collateral_pct_initial_gdp: 30, outstanding_liquidity_pct_initial_gdp: 31,
  liquidity_repayment_pct_initial_gdp: 32, liquidity_request_pct_initial_gdp: 33, liquidity_applied_pct_initial_gdp: 34,
  uncovered_funding_pct_initial_gdp: 35, credit_spread_pct: 36, credit_risk_wedge_pct: 37, solvency_risk_wedge_pct: 38,
  supply_pressure_pct: 39, credibility: 40, inflation_miss_memory_pct: 41, guidance_active: 42,
  guidance_rate_pct: 43, guidance_inflation_sensitivity: 44, guidance_output_gap_sensitivity: 45,
  guidance_reference_inflation_pct: 46, guidance_reference_output_gap_pct: 47, guidance_followthrough_score: 48,
  reaction_function_target_pct: 49, public_support: 50, public_hardship_memory: 51, current_hardship: 52,
  initial_annual_gdp_index: 53, price_h0: 54, price_h1: 55, price_h2: 56, price_h3: 57, price_h4: 58,
  prior_commitment: 60, priced_guidance: 61, expected_policy_path: 62, spot_gap: 63, inflation_pressure: 64,
  long_anchor: 65, inflation_performance: 66, stance_adequacy: 67, credibility_score: 68, support_target: 69,
  eligible_capacity: 70, loan_remaining: 71, lending_headroom: 72, policy_valid: 73, benchmark_rate: 75,
};
await fs.writeFile(new URL('workbook-model-map.json', evidence), JSON.stringify(R, null, 2));
for (const [key, row] of Object.entries(R)) cell(economy, `B${row}`, human(key));
cell(economy, 'B64', 'Annual gross price growth');
headers(economy, 'B4:AZ4');
economy.getRange('D5:AZ73').setNumberFormat('0.000');
const f = (col, key) => `${col}${R[key]}`;
for (let q = 0; q <= 48; q++) {
  const col = column(q + 4), previous = column(q + 3), s = key => f(col, key), prev = key => f(previous, key);
  const put = (key, formula) => cell(economy, s(key), `=${formula}`, true);
  cell(economy, s('quarter_index'), q);
  if (q === 0) {
    for (const key of Object.keys(source.initial_state).filter(k => R[k] && k !== 'quarter_index')) put(key, '0');
    for (const key of Object.keys(initialParameter)) put(key, initial(key));
    put('potential_output_index', p('initial_output_index'));
    put('actual_output_index', `${s('potential_output_index')}*(1+${s('output_gap_pct')}/100)`);
    for (const key of ['potential_growth_pct', 'annualized_potential_growth_pct', 'annualized_actual_growth_pct']) put(key, p('initial_potential_growth_pct'));
    put('price_index', p('initial_price_index'));
    put('initial_annual_gdp_index', p('initial_output_index'));
    put('initial_asset_stock_pct_initial_gdp', p('initial_asset_stock_pct_initial_gdp'));
    put('asset_stock_capacity_pct_initial_gdp', p('asset_stock_capacity_pct_initial_gdp'));
    put('last_policy_rate_request_pct', s('policy_rate_pct'));
    put('guidance_rate_pct', s('policy_rate_pct'));
    put('guidance_reference_inflation_pct', p('initial_inflation_rate_pct'));
    put('guidance_reference_output_gap_pct', p('initial_output_gap_pct'));
    put('guidance_followthrough_score', '1');
    put('reaction_function_target_pct', p('initial_policy_rate_pct'));
    put('long_yield_pct', `${s('policy_rate_pct')}+${s('term_premium_pct')}`);
    put('credit_spread_pct', `${p('normal_credit_spread_pct')}+${s('solvency_risk_wedge_pct')}`);
    for (let age = 0; age < 5; age++) put(`price_h${age}`, `${s('price_index')}/POWER(1+${s('annualized_quarterly_inflation_pct')}/100,${(4 - age) / 4})`);
    put('four_quarter_inflation_pct', `100*(${s('price_h4')}/${s('price_h0')}-1)`);
    continue;
  }
  const shock = key => `'Shocks'!${col}${shockRows.get(key)}`;
  const override = (row, fallback) => `IF(ISBLANK('Policy'!${col}${row}),${fallback},'Policy'!${col}${row})`;
  const requested = `CHOOSE('Policy Lab'!$C$6,${prev('r_star_pct')}+${prev('expected_short_inflation_pct')}+${p('policy_inflation_response')}*(${prev('four_quarter_inflation_pct')}-${p('inflation_target_pct')})+${p('policy_output_gap_response')}*${prev('output_gap_pct')},${prev('policy_rate_pct')})`;
  put('benchmark_rate', clamp(requested, p('policy_rate_min_pct'), p('policy_rate_max_pct')));
  put('last_policy_rate_request_pct', override(6, s('benchmark_rate')));
  const rateLimit = p('policy_rate_change_limit_pct');
  const appliedBenchmark = clamp(s('benchmark_rate'), `MAX(${p('policy_rate_min_pct')},${prev('policy_rate_pct')}-${rateLimit})`, `MIN(${p('policy_rate_max_pct')},${prev('policy_rate_pct')}+${rateLimit})`);
  const reachableQuote = clamp(s('benchmark_rate'), `MAX(${p('policy_rate_min_pct')},${appliedBenchmark}-${rateLimit})`, `MIN(${p('policy_rate_max_pct')},${appliedBenchmark}+${rateLimit})`);
  put('guidance_rate_pct', override(7, reachableQuote));
  put('guidance_inflation_sensitivity', override(8, p('policy_inflation_response')));
  put('guidance_output_gap_sensitivity', override(9, p('policy_output_gap_response')));
  put('asset_flow_request_pct_initial_gdp', `IF(ISNUMBER('Policy'!${col}10),'Policy'!${col}10,NA())`);
  put('liquidity_request_pct_initial_gdp', `IF(ISNUMBER('Policy'!${col}11),'Policy'!${col}11,NA())`);
  const controls = ['last_policy_rate_request_pct', 'guidance_rate_pct', 'guidance_inflation_sensitivity', 'guidance_output_gap_sensitivity', 'asset_flow_request_pct_initial_gdp', 'liquidity_request_pct_initial_gdp'];
  put('policy_valid', `AND(${controls.map(k => `ISNUMBER(${s(k)})`).join(',')},${s('last_policy_rate_request_pct')}>=${p('policy_rate_min_pct')},${s('last_policy_rate_request_pct')}<=${p('policy_rate_max_pct')},${s('guidance_rate_pct')}>=${p('policy_rate_min_pct')},${s('guidance_rate_pct')}<=${p('policy_rate_max_pct')},ABS(${s('guidance_inflation_sensitivity')})<=${p('guidance_sensitivity_limit')},ABS(${s('guidance_output_gap_sensitivity')})<=${p('guidance_sensitivity_limit')},ABS(${s('asset_flow_request_pct_initial_gdp')})<=${p('asset_flow_request_limit_pct_initial_gdp')},${s('liquidity_request_pct_initial_gdp')}>=0,${s('liquidity_request_pct_initial_gdp')}<=${p('liquidity_request_limit_pct_initial_gdp')})`);
  put('policy_rate_pct', `IF(${s('policy_valid')},${clamp(s('last_policy_rate_request_pct'), `MAX(${p('policy_rate_min_pct')},${prev('policy_rate_pct')}-${p('policy_rate_change_limit_pct')})`, `MIN(${p('policy_rate_max_pct')},${prev('policy_rate_pct')}+${p('policy_rate_change_limit_pct')})`)},NA())`);
  for (const key of ['initial_annual_gdp_index', 'initial_asset_stock_pct_initial_gdp', 'asset_stock_capacity_pct_initial_gdp']) put(key, prev(key));
  put('asset_flow_applied_pct_initial_gdp', clamp(s('asset_flow_request_pct_initial_gdp'), `-MIN(${p('asset_flow_quarter_limit_pct_initial_gdp')},${prev('asset_stock_pct_initial_gdp')})`, `MIN(${p('asset_flow_quarter_limit_pct_initial_gdp')},${prev('asset_stock_capacity_pct_initial_gdp')}-${prev('asset_stock_pct_initial_gdp')})`));
  put('asset_stock_pct_initial_gdp', `${prev('asset_stock_pct_initial_gdp')}+${s('asset_flow_applied_pct_initial_gdp')}`);
  put('term_premium_pct', `${prev('term_premium_pct')}-${p('term_premium_asset_sensitivity')}*${s('asset_flow_applied_pct_initial_gdp')}`);
  put('liquidity_repayment_pct_initial_gdp', `${prev('outstanding_liquidity_pct_initial_gdp')}*${p('liquidity_repayment_fraction')}`);
  put('loan_remaining', `${prev('outstanding_liquidity_pct_initial_gdp')}-${s('liquidity_repayment_pct_initial_gdp')}`);
  put('funding_need_pct_initial_gdp', shock('funding_need_pct_initial_gdp'));
  put('eligible_collateral_pct_initial_gdp', shock('eligible_collateral_pct_initial_gdp'));
  put('eligible_capacity', `${s('eligible_collateral_pct_initial_gdp')}*(1-${shock('collateral_haircut_pct')}/100)*${shock('liquidity_eligibility_pct')}/100`);
  put('lending_headroom', `MAX(0,${s('eligible_capacity')}-${s('loan_remaining')})`);
  put('liquidity_applied_pct_initial_gdp', `MIN(${s('liquidity_request_pct_initial_gdp')},${s('funding_need_pct_initial_gdp')},${p('liquidity_flow_quarter_limit_pct_initial_gdp')},${s('lending_headroom')})`);
  put('outstanding_liquidity_pct_initial_gdp', `${s('loan_remaining')}+${s('liquidity_applied_pct_initial_gdp')}`);
  put('uncovered_funding_pct_initial_gdp', `MAX(0,${s('funding_need_pct_initial_gdp')}-${s('liquidity_applied_pct_initial_gdp')})`);
  put('solvency_risk_wedge_pct', `${prev('solvency_risk_wedge_pct')}*${p('solvency_risk_persistence')}+${shock('solvency_risk_innovation_pct')}`);
  put('credit_risk_wedge_pct', `${p('funding_spread_sensitivity')}*${s('uncovered_funding_pct_initial_gdp')}+${s('solvency_risk_wedge_pct')}+${shock('credit_risk_innovation_pct')}`);
  put('credit_spread_pct', `${p('normal_credit_spread_pct')}+${s('credit_risk_wedge_pct')}`);
  put('prior_commitment', `IF(${prev('guidance_active')},${prev('guidance_rate_pct')}+${prev('guidance_inflation_sensitivity')}*(${prev('four_quarter_inflation_pct')}-${prev('guidance_reference_inflation_pct')})+${prev('guidance_output_gap_sensitivity')}*(${prev('output_gap_pct')}-${prev('guidance_reference_output_gap_pct')}),${s('policy_rate_pct')})`);
  put('guidance_followthrough_score', `IF(${prev('guidance_active')},EXP(-ABS(${s('policy_rate_pct')}-${s('prior_commitment')})/${p('credibility_followthrough_tolerance_pct')}),1)`);
  put('priced_guidance', `${s('policy_rate_pct')}+${prev('credibility')}*(${s('guidance_rate_pct')}-${s('policy_rate_pct')})`);
  put('expected_policy_path', `${p('long_yield_current_rate_weight')}*${s('policy_rate_pct')}+(1-${p('long_yield_current_rate_weight')})*${s('priced_guidance')}`);
  put('long_yield_pct', `${s('expected_policy_path')}+${s('term_premium_pct')}`);
  put('r_star_pct', `${prev('r_star_pct')}+${shock('r_star_change_pct')}`);
  put('spot_gap', `${p('real_rate_short_weight')}*(${s('policy_rate_pct')}-${prev('expected_short_inflation_pct')})+(1-${p('real_rate_short_weight')})*(${s('long_yield_pct')}-${p('initial_term_premium_pct')}-${prev('expected_long_inflation_pct')})+(${s('credit_spread_pct')}-${p('normal_credit_spread_pct')})-${s('r_star_pct')}`);
  put('financial_restraint_gap_pct', `${p('real_rate_gap_persistence')}*${prev('financial_restraint_gap_pct')}+(1-${p('real_rate_gap_persistence')})*${s('spot_gap')}`);
  put('potential_growth_pct', `IF(${shock('potential_growth_pct')}="unchanged",${prev('potential_growth_pct')},${shock('potential_growth_pct')})`);
  const structural = `${prev('structural_unemployment_pct')}+${shock('structural_unemployment_change_pct')}`;
  put('structural_unemployment_pct', `IF(AND(${structural}>0,${structural}<100),${structural},NA())`);
  put('potential_output_index', `${prev('potential_output_index')}*POWER(1+${s('potential_growth_pct')}/100,0.25)`);
  put('supply_pressure_pct', `${p('supply_pressure_persistence')}*${prev('supply_pressure_pct')}+${shock('supply_innovation_pct')}`);
  put('output_gap_pct', `${p('output_gap_persistence')}*${prev('output_gap_pct')}-${p('real_rate_output_sensitivity')}*${s('financial_restraint_gap_pct')}+${shock('demand_shock_pct')}-${p('supply_output_gap_sensitivity')}*${s('supply_pressure_pct')}`);
  const laborReference = s('structural_unemployment_pct'), laborGap = s('output_gap_pct'), laborSlope = p('unemployment_gap_sensitivity');
  const laborTarget = `IF(${laborGap}>=0,${laborReference}*EXP(-${laborSlope}*${laborGap}/${laborReference}),100-(100-${laborReference})*EXP(${laborSlope}*${laborGap}/(100-${laborReference})))`;
  put('unemployment_rate_pct', `${prev('unemployment_rate_pct')}+(1-${p('unemployment_gap_persistence')})*(${laborTarget}-${prev('unemployment_rate_pct')})`);
  put('inflation_pressure', `(${p('inflation_persistence')}*(1+${prev('annualized_quarterly_inflation_pct')}/100)+(1-${p('inflation_persistence')})*(1+${prev('expected_short_inflation_pct')}/100))*EXP((${p('inflation_output_gap_sensitivity')}*${prev('output_gap_pct')}+${p('inflation_supply_sensitivity')}*${s('supply_pressure_pct')})/(100+${p('inflation_target_pct')}))`);
  put('price_index', `${prev('price_index')}*POWER(${s('inflation_pressure')},0.25)`);
  for (let age = 0; age < 4; age++) put(`price_h${age}`, prev(`price_h${age + 1}`));
  put('price_h4', s('price_index'));
  put('four_quarter_inflation_pct', `100*(${s('price_h4')}/${s('price_h0')}-1)`);
  put('annualized_quarterly_inflation_pct', `100*(POWER(${s('price_index')}/${prev('price_index')},4)-1)`);
  put('expected_short_inflation_pct', `100*(((1-${p('short_expectation_recent_weight')})*(1+${prev('expected_short_inflation_pct')}/100)+${p('short_expectation_recent_weight')}*(1+${prev('four_quarter_inflation_pct')}/100))*EXP(${p('short_expectation_supply_sensitivity')}*${s('supply_pressure_pct')}/(100+${p('inflation_target_pct')}))-1)`);
  put('long_anchor', `${prev('credibility')}*${p('inflation_target_pct')}+(1-${prev('credibility')})*${prev('four_quarter_inflation_pct')}`);
  put('expected_long_inflation_pct', `${prev('expected_long_inflation_pct')}+${p('long_expectation_adjustment')}*(${s('long_anchor')}-${prev('expected_long_inflation_pct')})`);
  put('reaction_function_target_pct', `${s('r_star_pct')}+${prev('expected_short_inflation_pct')}+${p('policy_inflation_response')}*(${prev('four_quarter_inflation_pct')}-${p('inflation_target_pct')})+${p('policy_output_gap_response')}*${prev('output_gap_pct')}`);
  put('inflation_miss_memory_pct', `${p('credibility_miss_persistence')}*${prev('inflation_miss_memory_pct')}+(1-${p('credibility_miss_persistence')})*ABS(${prev('four_quarter_inflation_pct')}-${p('inflation_target_pct')})`);
  put('inflation_performance', `EXP(-${s('inflation_miss_memory_pct')}/${p('credibility_miss_tolerance_pct')})`);
  put('stance_adequacy', `EXP(-ABS(${s('policy_rate_pct')}-${s('reaction_function_target_pct')})/${p('credibility_stance_scale_pct')})`);
  put('credibility_score', `'Assumptions'!$D$69*${s('inflation_performance')}+'Assumptions'!$D$70*${s('stance_adequacy')}+'Assumptions'!$D$71*${s('guidance_followthrough_score')}`);
  put('credibility', clamp(`${prev('credibility')}+${p('credibility_adjustment')}*(${s('credibility_score')}-${prev('credibility')})`, 0, 1));
  put('current_hardship', `${p('public_inflation_burden_weight')}*ABS(${s('four_quarter_inflation_pct')}-${p('inflation_target_pct')})+${p('public_unemployment_burden_weight')}*MAX(0,${s('unemployment_rate_pct')}-${s('structural_unemployment_pct')})`);
  put('public_hardship_memory', `${p('public_hardship_memory_persistence')}*${prev('public_hardship_memory')}+(1-${p('public_hardship_memory_persistence')})*${s('current_hardship')}`);
  put('support_target', clamp(`${p('public_support_base')}-${s('current_hardship')}-${p('public_hardship_memory_weight')}*${s('public_hardship_memory')}`, 0, 100));
  put('public_support', `${prev('public_support')}+${p('public_support_adjustment')}*(${s('support_target')}-${prev('public_support')})`);
  put('actual_output_index', `${s('potential_output_index')}*(1+${s('output_gap_pct')}/100)`);
  put('annualized_actual_growth_pct', `100*(POWER(${s('actual_output_index')}/${prev('actual_output_index')},4)-1)`);
  put('annualized_potential_growth_pct', `100*(POWER(${s('potential_output_index')}/${prev('potential_output_index')},4)-1)`);
  put('guidance_active', 'TRUE');
  put('guidance_reference_inflation_pct', prev('four_quarter_inflation_pct'));
  put('guidance_reference_output_gap_pct', prev('output_gap_pct'));
}

// Player controls remain separate from the one calculation chain.
for (const sheet of [policy, shocks]) {
  sheet.getRange('E4:AZ4').values = [Array.from({ length: 48 }, (_, q) => q + 1)]; headers(sheet, 'B4:AZ4');
  cell(sheet, 'B4', 'Decision quarter');
}
for (const [row, label] of [[6, 'Rate request (%)'], [7, 'Next-quarter guidance (%)'], [8, 'Guidance: inflation response'], [9, 'Guidance: output-gap response'], [10, 'Asset flow (% initial GDP)'], [11, 'New liquidity (% initial GDP)']]) {
  cell(policy, `B${row}`, label); input(policy, `E${row}:AZ${row}`);
  if (row >= 10) policy.getRange(`E${row}:AZ${row}`).values = [[0]];
}
cell(policy, 'B13', 'Blanks in rows 6–9 follow the benchmark. Zero is an explicit override.');
cell(policy, 'B14', 'Guidance is conditional on the stated inflation/gap responses. Unreachable promises lose credibility.');
for (const [i, key] of ['policy_rate_pct', 'prior_commitment', 'guidance_followthrough_score', 'asset_flow_applied_pct_initial_gdp', 'liquidity_applied_pct_initial_gdp', 'outstanding_liquidity_pct_initial_gdp', 'credit_spread_pct', 'four_quarter_inflation_pct', 'unemployment_rate_pct', 'public_support'].entries()) {
  const row = 16 + i; cell(policy, `B${row}`, human(key));
  policy.getRange(`E${row}:AZ${row}`).formulas = [Array.from({ length: 48 }, (_, q) => `='Economy'!${column(q + 5)}${R[key]}`)];
}
policy.getRange('E6:AZ25').setNumberFormat('0.00');

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
    for (const [key, expected] of Object.entries(state)) {
      if (key === 'price_history') {
        expected.forEach((price, age) => assert.ok(Math.abs(economy.getRange(`${col}${R[`price_h${age}`]}`).values[0][0] - price) < 1e-7, `${label} q${q} price history ${age}`));
      } else {
        assert.ok(R[key], `State field missing from workbook: ${key}`);
        const actual = economy.getRange(`${col}${R[key]}`).values[0][0];
        const error = Math.abs(Number(actual) - Number(expected)); worst = Math.max(worst, error);
        assert.ok(Number.isFinite(Number(actual)) && error < 1e-7, `${label} q${q} ${key}: workbook ${actual}, Godot ${expected}`);
      }
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
assert.ok(Math.abs(economy.getRange('E20').values[0][0] - 2.75) < 1e-7, 'An explicit zero rate request is applied subject to the 75 bp change limit');
assert.ok(Math.abs(economy.getRange('E43').values[0][0] - 3.5) < 1e-7, 'Blank guidance follows its benchmark independently of a rate override');
cell(policy, 'E6', null); workbook.recalculate();
const variants = JSON.parse(await fs.readFile(new URL('./reference-v1/policy-variants.json', import.meta.url), 'utf8'));
for (const variant of variants) {
  cell(lab, 'C4', ids.indexOf(variant.case) + 1);
  const previous = policy.getRange(variant.cell).values[0][0];
  cell(policy, variant.cell, variant.value); workbook.recalculate();
  checks.push({ policyEdit: variant.name, maxAbsoluteError: verifyTrace(variant.name, variant.states) });
  cell(policy, variant.cell, previous);
}
// Real Godot boundary states use this same editable chain, not a second calculation.
const priceBoundaries = JSON.parse(await fs.readFile(new URL('./reference-v1/price-boundaries.json', import.meta.url), 'utf8'));
cell(lab, 'C4', 1); cell(lab, 'C6', 2);
for (const fixture of priceBoundaries) {
  const initialEdits = Object.keys(fixture.initial).map(key => [`D${initialRows.get(key) + 1}`, fixture.initial[key]]);
  const shockEdits = shockKeys.map(key => [`E${shockRows.get(key) + 1}`, fixture.shocks[0][key] ?? (key === 'potential_growth_pct' ? null : 0)]);
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
console.log('PASS: four policy edits, blank/zero distinction, missing-case isolation, invalid funding and later-period causality');
await fs.writeFile(new URL('workbook-parity.json', evidence), JSON.stringify(checks, null, 2));
console.log((await workbook.inspect({ kind: 'table', range: 'Policy Lab!B11:D17', include: 'values,formulas', tableMaxRows: 8, tableMaxCols: 4 })).ndjson);
console.log((await workbook.inspect({ kind: 'match', searchTerm: '#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!', options: { useRegex: true, maxResults: 20 }, summary: 'Formula error scan' })).ndjson);
await fs.mkdir(out, { recursive: true });
const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(fileURLToPath(new URL('Federal Reserve Policy Lab.xlsx', out)));
for (const [sheetName, range, file] of [['Policy Lab', 'A1:P55', 'lab'], ['Policy', 'A1:M26', 'policy'], ['Assumptions', 'A1:J18', 'assumptions'], ['Economy', 'A1:L23', 'economy'], ['Shocks', 'A1:L22', 'shocks']]) {
  const preview = await workbook.render({ sheetName, range, scale: 1, format: 'png' });
  await fs.writeFile(new URL(`workbook-${file}.png`, evidence), new Uint8Array(await preview.arrayBuffer()));
}
console.log('EXPORTED Federal Reserve Policy Lab.xlsx');
