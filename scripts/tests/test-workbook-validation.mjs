import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import { createHash } from 'node:crypto';

const source = await fs.readFile(new URL('../spreadsheet/build-policy-lab.mjs', import.meta.url), 'utf8');
const phaseStart = source.indexOf('const phaseCheckpoints = '), phaseEnd = source.indexOf('const buildPhase = ', phaseStart);
assert.ok(phaseStart >= 0 && phaseEnd > phaseStart, 'Require bounded main/hold/responsive phase admission before authoring');
const { phaseCheckpoints, parseBuildPhase, phaseOutputs } = vm.runInNewContext(`${source.slice(phaseStart, phaseEnd)}\n({phaseCheckpoints, parseBuildPhase, phaseOutputs})`, { assert });
assert.deepEqual(Object.fromEntries(Object.entries(phaseCheckpoints).map(([phase, indices]) => [phase, Array.from(indices)])),
  { main: [], hold: [0, 1, 2], responsive: [3, 4, 5] }, 'Exactly three ordered phases cover all six checkpoints once');
for (const phase of ['main', 'hold', 'responsive']) assert.equal(parseBuildPhase(['--phase', phase]), phase);
for (const args of [[], ['--phase'], ['--phase', 'all'], ['--phase', '__proto__'], ['--case', 'hold'], ['--phase', 'hold', '--case', 'base']]) {
  assert.throws(() => parseBuildPhase(args), /workbook phase/, 'Reject unknown/missing/conflicting modes before any artifact writes');
}
assert.ok(source.indexOf('const buildPhase = ') < source.indexOf('Workbook.create()'), 'Phase admission precedes workbook construction');
const outputs = ['main', 'hold', 'responsive'].flatMap(phase => Array.from(phaseOutputs(phase)));
assert.equal(new Set(outputs).size, outputs.length, 'Phases never overwrite each other outputs');
assert.equal(phaseOutputs('main').some(path => path.startsWith('late-checkpoints/')), false, 'Main has no unused late output');
for (const phase of ['hold', 'responsive']) {
  assert.deepEqual(Array.from(phaseOutputs(phase).filter(path => path.endsWith('.xlsx'))),
    [[120, 168], [168, 216], [216, 240]].map(([start, end]) => `late-checkpoints/late_${phase}_${start}_${end}.xlsx`));
}
const driver = await fs.readFile(new URL('../build-workbook.py', import.meta.url), 'utf8');
assert.match(driver, /BUILD_PHASES = \('main', 'hold', 'responsive'\)/, 'Driver has all three fixed ordered phases');
assert.match(driver, /for phase in BUILD_PHASES:/, 'Driver cannot select or omit a phase');
assert.match(driver, /str\(execution_copy\), '--phase', phase/, 'All modes execute the same source copy');
assert.match(driver, /f'workbook-build-\{phase\}\.log'/, 'Separate phase logs');
assert.match(driver, /f'COMPLETED workbook phase \{phase\}'/, 'Separate phase completion markers');
assert.match(driver, /timeout=900/, 'Keep the existing per-tool bound');
const aggregateStart = driver.indexOf("with (evidence / 'workbook-parity.json').open('x')");
const savedChecksEnd = driver.indexOf('    assert digest(builder) == digest(execution_copy)');
assert.ok(savedChecksEnd >= 0 && aggregateStart > savedChecksEnd, 'Final aggregate follows every saved-file check and source-copy assertion');
const preflightStart = source.indexOf('for (const path of phaseOutputs(buildPhase))'), preflightEnd = source.indexOf('const workbook = ', preflightStart);
assert.ok(preflightStart >= 0 && preflightEnd > preflightStart, 'Replacement preflight precedes authoring');
for (const buildPhase of ['main', 'hold', 'responsive']) {
  const paths = [];
  const runPreflight = exists => vm.runInNewContext(`(async () => { ${source.slice(preflightStart, preflightEnd)} })()`, {
    assert, phaseOutputs, buildPhase, URL, out: new URL('file:///private/tmp/phase-preflight/'),
    fs: { async access(path) {
      paths.push(path.pathname);
      if (!exists) throw Object.assign(new Error('missing'), { code: 'ENOENT' });
    } },
  });
  await runPreflight(false);
  assert.equal(paths.length, phaseOutputs(buildPhase).length);
  await assert.rejects(runPreflight(true), /Refusing phase output replacement/, 'Existing phase output stops before authoring');
}
const mainChecksStart = source.indexOf("if (buildPhase === 'main') {\nfor (let caseIndex = "), mainChecksEnd = source.indexOf('const checkpointFixtureEdits = ', mainChecksStart);
assert.ok(mainChecksStart > source.indexOf('const verifyTrace = ') && mainChecksEnd > mainChecksStart, 'Only main owns the unchanged original checks');
const mainChecks = source.slice(mainChecksStart, mainChecksEnd);
for (const family of ['policy-variants.json', 'price-boundaries.json', 'rate-boundaries.json', 'balance-boundaries.json']) assert.ok(mainChecks.includes(family), `Main retains ${family}`);
assert.ok(source.includes("if (buildPhase === 'hold') await fs.mkdir(lateDirectory);\nelse await fs.access(lateDirectory);"), 'Only hold creates the shared late output directory');
assert.ok(source.includes("else assert.deepEqual(JSON.parse(await fs.readFile(new URL('workbook-model-map.json', evidence), 'utf8')), R"), 'Late phases must match the same fresh formula row map');
const mainRenderStart = source.indexOf("if (buildPhase === 'main') {\nconsole.log('PASS: four policy edits");
assert.ok(mainRenderStart >= 0 && mainRenderStart < source.indexOf('await workbook.render('), 'Only main renders and writes the final cold workbook');
assert.ok(source.endsWith('console.log(`COMPLETED workbook phase ${buildPhase}`);\n'), 'Completion follows every phase check and export');
console.log('PASS: strict three-phase admission and complete nonoverlapping checkpoint partition (VM)');
const start = source.indexOf('const cell = '), end = source.indexOf('const human = ', start);
assert.ok(start >= 0 && end > start, 'Locate the actual workbook input helpers');
const { applyFixture, writeInputs } = vm.runInNewContext(`${source.slice(start, end)}\n({applyFixture, writeInputs: typeof writeInputs === 'function' ? writeInputs : null})`, { assert });
const events = [];
const originals = new Map([
  ['A1', { value: 7, formula: '' }], ['B1', { value: 0, formula: '' }],
  ['C1', { value: null, formula: '' }], ['D1', { value: 99, formula: '' }],
  ['E1', { value: false, formula: '' }], ['F1', { value: 14, formula: '=A1*2' }],
  ['Z2', { value: 7, formula: '' }], ['AA2', { value: 8, formula: '' }],
]);
const columnNumber = letters => [...letters].reduce((n, letter) => n * 26 + letter.charCodeAt(0) - 64, 0);
const columnName = n => { let s = ''; for (; n; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };
const sheet = { name: 'Inputs', getRange(ref) {
  const match = /^([A-Z]+)([1-9]\d*)(?::([A-Z]+)([1-9]\d*))?$/.exec(ref);
  assert.ok(match, `Unexpected fixture range ${ref}`);
  assert.equal(match[2], match[4] ?? match[2], 'Only one row is written');
  const records = Array.from({ length: columnNumber(match[3] ?? match[1]) - columnNumber(match[1]) + 1 }, (_, i) => originals.get(`${columnName(columnNumber(match[1]) + i)}${match[2]}`));
  assert.ok(records.every(Boolean), `Unexpected fixture cells ${ref}`);
  return {
    get values() { events.push(`read:${ref}`); return [records.map(x => x.value)]; },
    get formulas() { events.push(`formula:${ref}`); return [records.map(x => x.formula)]; },
    set values(matrix) { events.push(`write:${ref}`); assert.equal(matrix[0].length, records.length); records.forEach((x, i) => { x.value = matrix[0][i]; x.formula = ''; }); },
    set formulas(matrix) { events.push(`restore:${ref}`); assert.equal(matrix[0].length, records.length); records.forEach((x, i) => { x.formula = matrix[0][i]; }); },
  };
} };
const edits = ['A1', 'B1', 'C1', 'E1', 'F1'].map((ref, i) => [sheet, ref, [0, null, true, false, 21][i]]);
const saved = applyFixture(edits);
assert.equal(saved.length, edits.length);
assert.equal(events.slice(0, 10).some(x => x.startsWith('write:')), false, 'Read every original input before any edit');
assert.deepEqual(events.slice(10), ['write:A1:C1', 'write:E1:F1'], 'Batch contiguous row inputs without overwriting gaps');
assert.deepEqual(Array.from(saved, ([, ref, value, formula]) => [ref, value, formula]), [
  ['A1', 7, ''], ['B1', 0, ''], ['C1', null, ''], ['E1', false, ''], ['F1', 14, '=A1*2'],
]);
assert.deepEqual(edits.map(([, ref]) => originals.get(ref).value), [0, null, true, false, 21]);
writeInputs(saved.map(([target, ref, value, formula]) => [target, ref, formula || value, Boolean(formula)]));
assert.equal(originals.get('F1').formula, '=A1*2', 'Restore formulas, not stale cached values');
assert.deepEqual(['A1', 'B1', 'C1', 'E1'].map(ref => originals.get(ref).value), [7, 0, null, false]);
assert.equal(originals.get('D1').value, 99, 'An unedited gap remains unchanged');
assert.equal(applyFixture([]).length, 0);
events.length = 0;
assert.throws(() => applyFixture([[sheet, 'A1', 9], [sheet, 'Dundefined', 9]]), /Unmapped boundary input/);
assert.equal(events.some(x => x.startsWith('write:')), false, 'Reject unmapped inputs before mutation');
writeInputs([[sheet, 'AA2', 0], [sheet, 'Z2', false]]);
assert.deepEqual(events.filter(x => x.startsWith('write:')), ['write:Z2:AA2'], 'Sort columns numerically across Z/AA');
assert.equal(originals.get('Z2').value, false); assert.equal(originals.get('AA2').value, 0);
events.length = 0;
writeInputs([[sheet, 'Z2', '=A1', true], [sheet, 'AA2', 0]]);
assert.deepEqual(events, ['restore:Z2:Z2', 'write:AA2:AA2'], 'Do not mix formulas and literal values in one write');
let otherValue = 97;
const otherSheet = { name: 'Other', getRange(ref) {
  assert.equal(ref, 'A1:A1');
  return { set values(matrix) { otherValue = matrix[0][0]; } };
} };
writeInputs([[sheet, 'A1', 11], [otherSheet, 'A1', 22]]);
assert.equal(originals.get('A1').value, 11); assert.equal(otherValue, 22, 'Do not merge rows across sheets');
console.log('PASS: actual workbook helper batches exact typed inputs/restores, preserving gaps and formula boundaries (simulated cells)');

const formatStart = source.indexOf('economy.getRange(`D100:AZ${nextModelRow - 1}`).setNumberFormat'),
  formatEnd = source.indexOf('for (let q = 0; q <= 48;', formatStart);
assert.ok(formatStart >= 0 && formatEnd > formatStart, 'Locate final calculation-row formatting');
const R = { guidance_active: 42, policy_valid: 73, reinvest_principal: 410, maintain_ample_reserves: 411, sterilize_purchases: 412 };
const formats = new Map([...Object.values(R), 123].map(row => [row, '0.000']));
vm.runInNewContext(source.slice(formatStart, formatEnd), {
  R, nextModelRow: 413, economy: { getRange(ref) {
    const range = /^D(\d+):AZ(\d+)$/.exec(ref);
    assert.ok(range, `Unexpected calculation formatting range ${ref}`);
    return { setNumberFormat(format) {
      for (const row of formats.keys()) if (row >= Number(range[1]) && row <= Number(range[2])) formats.set(row, format);
    } };
  } },
});
for (const row of Object.values(R)) assert.equal(formats.get(row), 'General', 'Logical calculation results must not inherit numeric formatting');
assert.equal(formats.get(123), '0.000', 'Numeric calculation rows retain their precision');
console.log('PASS: actual final formatting preserves all five logical rows and numeric precision (simulated ranges)');

const quoteStart = source.indexOf('const quote = '), quoteEnd = source.indexOf('const effective = ', quoteStart);
const policyInputStart = source.indexOf("  put('decision_nominal_gdp_ratio', `("),
  policyInputEnd = source.indexOf("  for (const key of ['initial_annual_gdp_index'", policyInputStart);
assert.ok(quoteStart >= 0 && quoteEnd > quoteStart && policyInputStart >= 0 && policyInputEnd > policyInputStart,
  'Locate the actual quote helpers and six-control policy input/qualification emitter');
const policyExpressions = new Map();
const policyContext = vm.createContext({
  col: 'E', s: key => `state.${key}`, prev: key => `previous.${key}`, p: key => `parameters.${key}`,
  shockRows: new Map(), put: (key, formula) => policyExpressions.set(key, formula),
});
vm.runInContext(source.slice(quoteStart, quoteEnd), policyContext);
const emittedGridExpression = vm.runInContext("onGrid('value')", policyContext);
const numericControls = Array.from(vm.runInContext(`${source.slice(policyInputStart, policyInputEnd)}\ncontrols`, policyContext));
assert.deepEqual(numericControls, ['last_policy_rate_request_pct', 'guidance_rate_pct', 'guidance_inflation_sensitivity',
  'guidance_output_gap_sensitivity', 'asset_flow_request_pct_initial_gdp', 'liquidity_request_pct_initial_gdp']);
const policyValidationStart = source.indexOf('for (const [range, formula] of ['),
  policyValidationEnd = source.indexOf("cell(policy, 'B16'", policyValidationStart);
assert.ok(policyValidationStart >= 0 && policyValidationEnd > policyValidationStart, 'Locate the actual numeric-input Stop validation emitter');
const policyValidations = new Map();
policyContext.policy = { getRange(ref) { return { set dataValidation(value) { policyValidations.set(ref, value); } }; } };
vm.runInContext(source.slice(policyValidationStart, policyValidationEnd), policyContext);
assert.deepEqual([...policyValidations.keys()], ['E6:AZ9', 'E10:AZ11'], 'Only six numeric controls receive validation; Boolean switches stay untouched');
for (const [range, formula] of [['E6:AZ9', 'OR(ISBLANK(E6),AND(ISNUMBER(E6),NOT(ISLOGICAL(E6))))'],
  ['E10:AZ11', 'AND(ISNUMBER(E10),NOT(ISLOGICAL(E10)))']]) {
  const validation = policyValidations.get(range);
  assert.equal(validation.rule.type, 'custom');
  assert.equal(validation.rule.formula1, formula, 'Keep the type predicate relative to the range top-left; add no economic thresholds');
  assert.equal(validation.ignoreBlanks, false, 'Explicit ISBLANK alone allows the four optional overrides');
  assert.equal(validation.errorAlert.show, true);
  assert.equal(validation.errorAlert.style, 'stop');
  assert.equal(validation.errorAlert.title, 'Number required');
  assert.equal(validation.errorAlert.message, 'Enter a number, not TRUE/FALSE. Blanks are allowed only in rows 6–9.');
}
const policyNotes = new Map();
vm.runInNewContext(source.slice(policyValidationEnd, source.indexOf('const endingStocks = ', policyValidationEnd)), {
  policy: {}, cell: (_, ref, value) => policyNotes.set(ref, value),
});
assert.equal(policyNotes.get('B19'), "After invalid paste: set the input's number format to General, then re-enter.", 'Recovery changes only the affected number format before re-entry');
const evaluateInputValidation = (row, value, logicalIsNumeric) => vm.runInNewContext(
  policyValidations.get(row < 10 ? 'E6:AZ9' : 'E10:AZ11').rule.formula1.replace(/E\d+/g, 'value'), {
    value, OR: (...values) => values.some(Boolean), AND: (...values) => values.every(Boolean), NOT: value => !value,
    ISBLANK: value => value === null || value === undefined, ISLOGICAL: value => typeof value === 'boolean',
    ISNUMBER: value => typeof value === 'number' && Number.isFinite(value) || logicalIsNumeric && typeof value === 'boolean',
  });
const policyInputFormatStart = source.indexOf("policy.getRange('E6:AZ11').setNumberFormat"),
  policyInputFormatEnd = source.indexOf("policy.getRange('E20:AZ39')", policyInputFormatStart);
assert.ok(policyInputFormatStart >= 0 && policyInputFormatEnd > policyInputFormatStart);
const policyInputFormats = new Map();
vm.runInNewContext(source.slice(policyInputFormatStart, policyInputFormatEnd), {
  policy: { getRange(ref) {
    assert.equal(ref, 'E6:AZ11');
    return { setNumberFormat(format) { for (let row = 6; row <= 11; row++) policyInputFormats.set(row, format); } };
  } },
});
// Calc can turn a logical result into 0/1 in a numeric-formatted cell before ISLOGICAL reads it.
const formattedPolicyValue = (value, format, logicalIsNumeric) =>
  logicalIsNumeric && format !== 'General' && typeof value === 'boolean' ? Number(value) : value;
// Evaluate only these emitted trust-boundary expressions, not a spreadsheet or the economic model.
const policyScript = new vm.Script(`const state = {};\n${[...policyExpressions].map(([key, expression]) =>
  `state.${key} = CACHE(${expression.replaceAll("'Policy Lab'!$C$6", 'benchmarkKind').replace(/'Policy'!E(\d+)/g, 'inputs[$1]')}, '${key}');`).join('\n')}\nstate`);
const policyParameters = Object.fromEntries(JSON.parse(await fs.readFile(new URL('../../game/model/parameters.json', import.meta.url), 'utf8')).map(({ key, value }) => [key, value]));
const previousPolicyState = { actual_output_index: 200, initial_actual_output_index: 100, price_index: 100,
  initial_price_index: 100, r_star_pct: 1.5, expected_short_inflation_pct: 2, four_quarter_inflation_pct: 2,
  output_gap_pct: 0, policy_rate_pct: -0.25 };
const policyDefaults = { 6: null, 7: null, 8: null, 9: null, 10: 0, 11: 0, 12: true, 13: true, 14: false };
const evaluatePolicy = (edits, logicalIsNumeric, parameters = policyParameters, benchmarkKind = 1) => policyScript.runInNewContext({
  inputs: Object.fromEntries(Object.entries({ ...policyDefaults, ...edits }).map(([row, value]) =>
    [row, formattedPolicyValue(value, policyInputFormats.get(Number(row)) ?? 'General', logicalIsNumeric)])),
  CACHE: (value, key) => formattedPolicyValue(value, formats.get(R[key] ?? 123), logicalIsNumeric), previous: previousPolicyState, parameters, benchmarkKind,
  TRUE: true, FALSE: false, NA: () => '#N/A',
  IF: (condition, yes, no) => condition === '#N/A' ? condition : condition ? yes : no,
  AND: (...values) => values.includes('#N/A') ? '#N/A' : values.every(Boolean), NOT: value => !value,
  ISBLANK: value => value === null || value === undefined, ISLOGICAL: value => typeof value === 'boolean',
  ISNUMBER: value => typeof value === 'number' && Number.isFinite(value) || logicalIsNumeric && typeof value === 'boolean',
  ABS: Math.abs, SIGN: Math.sign, ROUND: (value, digits) => Math.sign(value) * Math.round(Math.abs(value) * 10 ** digits) / 10 ** digits,
  CHOOSE: (index, ...values) => values[index - 1],
});
for (const [engine, logicalIsNumeric] of [['Excel', false], ['Calc', true]]) {
  for (let row = 6; row <= 11; row++) {
    for (const value of [true, false, '1', '', '#VALUE!', NaN, Infinity]) {
      assert.equal(evaluateInputValidation(row, value, logicalIsNumeric), false, `${engine} Stop predicate rejects E${row}=${String(value)}`);
    }
    for (const value of [-1000, -3.501, -0.25, 0, 0.25, 3.501, 1000]) {
      assert.equal(evaluateInputValidation(row, value, logicalIsNumeric), true, 'Type-only validation adds no rate/grid/sensitivity/offer restrictions');
    }
    for (const value of [null, undefined]) assert.equal(evaluateInputValidation(row, value, logicalIsNumeric), row < 10, 'Only four optional controls allow actual blanks');
  }
  const defaults = evaluatePolicy({}, logicalIsNumeric);
  assert.equal(defaults.policy_valid, true, `${engine} preserves valid blank/default policy`);
  assert.equal(defaults.policy_rate_pct, 3.5);
  assert.equal(defaults.guidance_rate_pct, 3.5);
  assert.equal(defaults.guidance_inflation_sensitivity, policyParameters.policy_inflation_response);
  assert.equal(defaults.guidance_output_gap_sensitivity, policyParameters.policy_output_gap_response);
  const hold = evaluatePolicy({}, logicalIsNumeric, policyParameters, 2);
  assert.equal(hold.policy_valid, true); assert.equal(hold.policy_rate_pct, -0.25); assert.equal(hold.guidance_rate_pct, -0.25);
  for (const [i, key] of numericControls.entries()) {
    for (const value of [true, false, '1', '', '#VALUE!', NaN, Infinity]) {
      const result = evaluatePolicy({ [6 + i]: value }, logicalIsNumeric);
      assert.notEqual(result.policy_valid, true, `${engine} raw E${6 + i}=${String(value)} must reject ${key}`);
      assert.equal(result.policy_rate_pct, '#N/A', `${engine} invalid numeric control cannot apply policy`);
      if (i >= 4) assert.equal(result[key], '#N/A', 'Reject raw asset/lending type before GDP multiplication erases it');
    }
  }
  for (const row of [6, 7]) {
    for (const value of [-100, -3.51, -0.01, 0, 0.01, 3.51, 100]) {
      const result = evaluatePolicy({ [row]: value }, logicalIsNumeric);
      assert.equal(result.policy_valid, true, 'Zero and signed grid quotes remain admissible without a rate cap');
      assert.equal(result[row === 6 ? 'policy_rate_pct' : 'guidance_rate_pct'], value);
      assert.equal(result[row === 6 ? 'guidance_rate_pct' : 'policy_rate_pct'], 3.5, 'Blank rate/guidance falls back independently');
    }
    for (const value of [-3.501, 3.501]) assert.equal(evaluatePolicy({ [row]: value }, logicalIsNumeric).policy_rate_pct, '#N/A', 'Off-grid quotes remain rejected');
    const widerGrid = { ...policyParameters, minimum_rate_increment_pct: 0.02 };
    assert.equal(evaluatePolicy({ [row]: 3.52 }, logicalIsNumeric, widerGrid).policy_valid, true);
    assert.equal(evaluatePolicy({ [row]: 3.51 }, logicalIsNumeric, widerGrid).policy_rate_pct, '#N/A', 'Use the declared minimum increment');
    for (const increment of [0, '#N/A']) assert.equal(evaluatePolicy({}, logicalIsNumeric,
      { ...policyParameters, minimum_rate_increment_pct: increment }).policy_rate_pct, '#N/A', 'Unavailable/zero increment cannot produce a valid quote');
  }
  for (const row of [8, 9]) {
    for (const value of [-2, 0, 2]) assert.equal(evaluatePolicy({ [row]: value }, logicalIsNumeric).policy_valid, true, 'Signed sensitivity limit endpoints remain valid');
    for (const value of [-2.001, 2.001]) assert.equal(evaluatePolicy({ [row]: value }, logicalIsNumeric).policy_rate_pct, '#N/A', 'Sensitivity limits remain enforced');
  }
  for (const [row, values] of [[10, [-1000, 0, 1000]], [11, [0, 1000]]]) {
    for (const value of values) {
      const result = evaluatePolicy({ [row]: value }, logicalIsNumeric);
      assert.equal(result.policy_valid, true, 'Valid finite offers retain their existing domain');
      assert.equal(result[numericControls[row - 6]], value * 2, 'Convert a numeric offer once using prior meeting GDP');
    }
    assert.equal(evaluatePolicy({ [row]: null }, logicalIsNumeric).policy_rate_pct, '#N/A', 'Blank offers do not inherit rate/guidance fallback');
  }
  assert.equal(evaluatePolicy({ 11: -0.01 }, logicalIsNumeric).policy_rate_pct, '#N/A', 'Negative lending remains invalid');
  const switches = ['reinvest_principal', 'maintain_ample_reserves', 'sterilize_purchases'];
  for (let bits = 0; bits < 8; bits++) {
    const edits = Object.fromEntries(switches.map((_, i) => [12 + i, Boolean(bits & (1 << i))]));
    const result = evaluatePolicy(edits, logicalIsNumeric);
    assert.equal(result.policy_valid, true, 'Every legitimate Boolean switch combination remains valid');
    for (const [i, key] of switches.entries()) assert.equal(result[key], edits[12 + i], 'Preserve switch Boolean type and value');
  }
  for (const row of [12, 13, 14]) for (const value of [0, 1, 'TRUE', null]) {
    assert.equal(evaluatePolicy({ [row]: value }, logicalIsNumeric).policy_rate_pct, '#N/A', 'Numeric/text/blank switches stay invalid');
  }
  for (const value of [true, false]) assert.equal(vm.runInNewContext(emittedGridExpression, {
      value, parameters: policyParameters, IF: (condition, yes, no) => condition ? yes : no,
      AND: (...values) => values.every(Boolean), NOT: value => !value, ISLOGICAL: value => typeof value === 'boolean',
      ISNUMBER: value => typeof value === 'number' || logicalIsNumeric && typeof value === 'boolean', ABS: Math.abs, ROUND: Math.round, FALSE: false,
    }), false, `${engine} actual shared grid helper rejects Boolean quotes`);
}
console.log('PASS: actual six-control policy emitters reject Boolean inputs under Excel/Calc classifications; numeric domains, independent blanks and Boolean switches preserved (VM/simulated; not native recalculation)');
console.log('PASS: actual numeric-input Stop rules preserve relative ranges, strict types, four optional blanks and format-only recovery guidance (VM/simulated; native prevention unqualified)');

const selectorStart = source.indexOf('for (const [address, max] of '), selectorEnd = source.indexOf("cell(lab, 'B8'", selectorStart);
assert.ok(selectorStart >= 0 && selectorEnd > selectorStart, 'Locate the actual selector validation emitter');
const selectorRules = new Map();
vm.runInNewContext(source.slice(selectorStart, selectorEnd), {
  cases: Array(7), lab: { getRange(ref) { return { set dataValidation(value) { selectorRules.set(ref, value.rule); } }; } },
});
const horizonFormula = 'COUNTA($B$58:$B$106)-1', quarterRule = selectorRules.get('C5');
assert.equal(quarterRule.type, 'whole'); assert.equal(quarterRule.operator, 'between');
assert.equal(quarterRule.formula1, 0);
assert.equal(quarterRule.formula2, horizonFormula, 'Quarter validation must follow the available calendar, not a fixed 48');
const summaryStart = source.indexOf('const metrics = '), summaryEnd = source.indexOf("lab.getRange('C12:C17')", summaryStart);
assert.ok(summaryStart >= 0 && summaryEnd > summaryStart, 'Locate the actual six-metric summary emitter');
const summaryCells = new Map(), metricRows = { four_quarter_inflation_pct: 13, unemployment_rate_pct: 16,
  output_gap_pct: 9, policy_rate_pct: 20, credibility: 40, public_support: 50 };
vm.runInNewContext(source.slice(summaryStart, summaryEnd), {
  R: metricRows, lab: {}, cell: (_, ref, value, formula) => { if (formula) summaryCells.set(ref, value); },
});
assert.equal(summaryCells.size, 6, 'Guard every headline metric');
const summaryFormats = new Map();
vm.runInNewContext(source.slice(summaryEnd, source.indexOf("cell(lab, 'F12'", summaryEnd)), {
  lab: { getRange(ref) { if (!summaryFormats.has(ref)) summaryFormats.set(ref, {}); return { format: summaryFormats.get(ref), setNumberFormat() {} }; } },
});
assert.equal(summaryFormats.get('C12:C17')?.horizontalAlignment, 'right', 'Unavailable text must align with numeric summaries');
assert.equal(summaryFormats.get('D11:D17')?.horizontalAlignment, 'center', 'Separate units from right-aligned values');
const guard = `AND(ISNUMBER($C$5),NOT(ISLOGICAL($C$5)),$C$5=INT($C$5),$C$5>=0,$C$5<=${horizonFormula})`;
for (const [i, row] of Object.values(metricRows).entries()) assert.equal(summaryCells.get(`C${12 + i}`),
  `=IF(IFERROR(${guard},FALSE),INDEX('Economy'!$D$${row}:$AZ$${row},1,$C$5+1),"n.a.")`,
  'Check numeric/integer/calendar bounds before INDEX; bypassed invalid selectors must be unavailable');
const emittedGuard = summaryCells.get('C12').match(/^=IF\(IFERROR\((AND\(.*\)),FALSE\),INDEX\(/)[1];
const verifySummaryHorizon = (labels, horizon) => {
  assert.equal(labels.filter(value => value !== null && value !== undefined && value !== '').length - 1, horizon);
  const states = Array.from({ length: 49 }, (_, offset) => ({ offset }));
  const select = (offset, logicalIsNumeric = false) => {
    let valid = false;
    // Evaluate only the emitted selector guard, not Excel or any economic formula.
    try {
      valid = vm.runInNewContext(emittedGuard.replaceAll('COUNTA($B$58:$B$106)', 'COUNTA(labels)')
        .replaceAll('$C$5=INT($C$5)', 'EQUAL(offset,INT(offset))').replaceAll('$C$5', 'offset'), {
        offset, labels, AND: (...values) => values.every(Boolean), NOT: value => !value, ISLOGICAL: value => typeof value === 'boolean',
        ISNUMBER: value => typeof value === 'number' && Number.isFinite(value) || logicalIsNumeric && typeof value === 'boolean',
        EQUAL: (a, b) => logicalIsNumeric ? Number(a) === b : a === b,
        INT: value => { if (typeof value === 'boolean') return Number(value); if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('Invalid numeric selector'); return Math.floor(value); },
        COUNTA: values => values.filter(value => value !== null && value !== undefined && value !== '').length,
      });
    } catch { /* IFERROR rejects an invalid selector before INDEX. */ }
    return valid ? states[offset] : 'n.a.';
  };
  for (const offset of new Set([0, horizon, 24, 25, 48])) assert.equal(select(offset), offset <= horizon ? states[offset] : 'n.a.', 'Preserve endpoints; never select an unvalidated suffix');
  for (const offset of [-1, horizon + 1, 0.5, '0', '25', '', null, undefined, true, false, NaN, Infinity, { error: '#VALUE!' }]) {
    assert.equal(select(offset), 'n.a.', 'Negative/fraction/text/blank/error bypasses must not select a plausible state');
  }
  for (const logicalIsNumeric of [false, true]) {
    for (const offset of [true, false]) assert.equal(select(offset, logicalIsNumeric), 'n.a.', 'Reject logical offsets under both Excel and Calc number classifications (simulated)');
    for (const offset of [0, horizon]) assert.equal(select(offset, logicalIsNumeric), states[offset], 'Preserve numeric endpoints under both classifications');
  }
};
const calendarStart = source.indexOf('for (let q = 0; q <= 48;', source.indexOf('const plotKeys = ')), calendarEnd = source.indexOf('const chart = ', calendarStart);
assert.ok(calendarStart >= 0 && calendarEnd > calendarStart, 'Locate the actual main calendar emitter');
const mainLabels = new Map();
vm.runInNewContext(source.slice(calendarStart, calendarEnd), {
  lab: { getRange() { return { set formulas(_) {} }; } }, plotKeys: [], R: {}, column: columnName,
  cell: (_, ref, value) => mainLabels.set(ref, value),
});
verifySummaryHorizon(Array.from({ length: 49 }, (_, q) => mainLabels.get(`B${q + 58}`)), 48);
for (const [ref, value] of mainLabels) originals.set(ref, { value, formula: '' });
console.log('PASS: actual selector/summary/calendar emitters reject invalid offsets (VM/simulated guards; not native recalculation)');

if (process.argv.length > 2) {
  assert.equal(process.argv[2], '--checkpoint-reference');
  assert.equal(process.argv.length, 4, 'Usage: --checkpoint-reference /absolute/late-checkpoints.json');
  const fixtures = JSON.parse(await fs.readFile(process.argv[3], 'utf8'));
  assert.equal(fixtures.length, 6, 'Two continuous branches, each with three checkpoint segments');
  const flattenStart = source.indexOf('const arrayShapes = '), flattenEnd = source.indexOf('const nominalKeys = ', flattenStart);
  const { arrayShapes, flattenState } = vm.runInNewContext(`${source.slice(flattenStart, flattenEnd)}\n({arrayShapes, flattenState})`, { assert });
  const mapStart = source.indexOf('const R = {'), mapEnd = source.indexOf('const sourceStart = ', mapStart);
  const native = fixtures[0].initial_state;
  assert.equal(Object.keys(flattenState(native)).length, 373, 'Retain the complete source-state contract');
  const { R: rows } = vm.runInNewContext(`${source.slice(mapStart, mapEnd)}\n({R})`, { flattenState, source: { initial_state: native } });
  const originalBases = ['initial_annual_gdp_index', 'initial_actual_output_index', 'initial_price_index',
    'initial_asset_stock_pct_initial_gdp', 'initial_duration_equivalent_pct_initial_gdp', 'initial_portfolio_premium_pct', 'initial_mbs_financing_rate_pct'];
  for (const [i, fixture] of fixtures.entries()) {
    assert.equal(fixture.schema, 'fed-economic-reference-v1', 'Use the existing strict saved-file reference contract');
    assert.equal(fixture.scenario.id, 'unanchored_inflation');
    assert.equal(fixture.seed, 1);
    assert.equal(fixture.warmup_policy_kind, 'feedback');
    assert.equal(fixture.policy_kind, i < 3 ? 'hold' : 'responsive');
    assert.equal(fixture.start_quarter, [120, 168, 216][i % 3]);
    assert.equal(fixture.end_quarter, [168, 216, 240][i % 3]);
    assert.equal(fixture.initial_state.quarter_index, fixture.start_quarter);
    assert.equal(fixture.quarters.length + 1, [49, 49, 25][i % 3]);
    assert.equal(fixture.shock_path.length, fixture.quarters.length);
    if (i % 3) assert.deepEqual(fixture.initial_state, fixtures[i - 1].quarters.at(-1).state, 'Segment boundary is the exact prior state');
    else assert.deepEqual(fixture.initial_state, native, 'Both branches share the complete Q120 checkpoint');
    for (const [name, hash] of Object.entries(fixture.source_sha256)) {
      const bytes = await fs.readFile(new URL(`../../game/${name}`, import.meta.url));
      assert.equal(createHash('sha256').update(bytes).digest('hex'), hash, `Native source binding: ${name}`);
    }
    assert.equal(createHash('sha256').update(fixture.portfolio_reference_json).digest('hex'), fixture.portfolio_reference_sha256);
    let prior = fixture.initial_state;
    for (const [q, row] of fixture.quarters.entries()) {
      assert.equal(row.quarter_index, fixture.start_quarter + q + 1);
      assert.equal(row.state.quarter_index, row.quarter_index);
      assert.deepEqual(row.shock, fixture.shock_path[q], 'Record the actual shared realized shock');
      assert.equal(row.policy.asset_flow_request_pct_initial_gdp, 0);
      for (const key of ['reinvest_principal', 'maintain_ample_reserves', 'sterilize_purchases']) assert.equal(Object.hasOwn(row.policy, key), false, 'No portfolio switches beyond existing native defaults');
      const offered = fixture.policy_kind === 'hold' ? 0 : (row.shock.funding_need_pct_initial_gdp ?? 0)
        + Math.min(row.shock.refinancing_need_pct_initial_gdp ?? 0, prior.outstanding_liquidity_pct_initial_gdp);
      assert.equal(row.policy.liquidity_request_pct_initial_gdp, offered, 'Lending uses only current shock and prior loan principal');
      if (fixture.policy_kind === 'hold') assert.equal(row.policy.policy_rate_request_pct, prior.policy_rate_pct, 'Hold retains the prior nominal quote');
      for (const key of originalBases) assert.equal(row.state[key], native[key], `Never rebase ${key}`);
      prior = row.state;
    }
    for (const state of [fixture.initial_state, ...fixture.quarters.map(row => row.state)]) {
      for (const [key, size] of Object.entries(arrayShapes)) assert.equal(state[key]?.length, size, `Full-state array required: ${key}`);
      const fields = flattenState(state);
      assert.deepEqual(Object.keys(fields).sort(), Object.keys(flattenState(native)).sort(), 'Retain every full-state field and cohort');
      for (const [key, value] of Object.entries(fields)) {
        assert.ok(rows[key], `Full-state parity unmapped native field: ${key}`);
        assert.equal(typeof value, key === 'guidance_active' ? 'boolean' : 'number', `Native finite type: ${key}`);
        if (typeof value === 'number') assert.ok(Number.isFinite(value), `Native finite value: ${key}`);
      }
    }
  }
  console.log('PASS: source-bound native segments, complete finite states, exact boundaries and current-input/prior-state lending');

  // Run the actual cold-column emitter, not an invented checkpoint or formula evaluator.
  const records = new Map();
  const economy = { name: 'Economy', getRange(ref) {
    const match = /^(D\d+)(?::\1)?$/.exec(ref);
    assert.ok(match, `Unexpected checkpoint range ${ref}`);
    if (!records.has(match[1])) records.set(match[1], { value: null, formula: '' });
    const record = records.get(match[1]);
    return {
      get values() { return [[record.value]]; },
      get formulas() { return [[record.formula]]; },
      set values(matrix) { record.value = matrix[0][0]; record.formula = ''; },
      set formulas(matrix) { record.formula = matrix[0][0]; },
    };
  } };
  const initialStart = source.indexOf('const initialParameter = '), initialEnd = source.indexOf('const initialRows = ', initialStart);
  const { initialParameter } = vm.runInNewContext(`${source.slice(initialStart, initialEnd)}\n({initialParameter})`);
  const coldStart = source.indexOf('for (let q = 0; q <= 48;'), coldEnd = source.indexOf('    continue;', coldStart);
  assert.ok(coldStart >= 0 && coldEnd > coldStart, 'Locate the actual cold first-column initialization');
  vm.runInNewContext(`${source.slice(coldStart, coldEnd)}\n    break;\n  }\n}`, {
    column: columnName, f: (col, key) => `${col}${rows[key]}`, cell: (target, ref, value, formula) => {
      target.getRange(ref)[formula ? 'formulas' : 'values'] = [[value]];
    }, economy, source: { initial_state: native }, flattenState, initialParameter,
    initialFields: Object.keys(initialParameter), initial: key => `'Assumptions'!${key}`,
    p: key => `'Assumptions'!${key}`, sourceStart: 1000,
    arrayField: (key, i) => key === 'price_history' ? `price_h${i}` : `${key}_${i}`,
    treasuryKey: 'treasury_cohorts_pct_initial_gdp', tagKey: 'sterilized_treasury_cohorts_pct_initial_gdp', billKey: 'bill_cohorts_pct_initial_gdp',
    cohortSum: () => 'SUM(D100:D219)', writeRateConditions: () => {},
  });
  const { checkpointEdits } = vm.runInNewContext(`${source.slice(start, end)}\n({checkpointEdits: typeof checkpointEdits === 'function' ? checkpointEdits : null})`, { assert, flattenState, source: { initial_state: native } });
  const verifyStart = source.indexOf('const verifyTrace = '), verifyEnd = source.indexOf('const policyRows = ', verifyStart);
  const verifyTrace = vm.runInNewContext(`${source.slice(verifyStart, verifyEnd)}\nverifyTrace`, { assert, economy, R: rows, column: columnName, flattenState });
  if (!checkpointEdits) {
    console.log('RED evidence (static emitter/simulated cells; formulas are not calculated):', JSON.stringify({
      quarter: { actual: records.get(`D${rows.quarter_index}`).value, expected: native.quarter_index },
      history: { actual_formula: records.get(`D${rows.price_h0}`).formula, expected_levels: native.price_history },
      bases: { actual_output_formula: records.get(`D${rows.initial_actual_output_index}`).formula,
        actual_price_formula: records.get(`D${rows.initial_price_index}`).formula,
        original_output: native.initial_actual_output_index, current_output: native.actual_output_index,
        original_price: native.initial_price_index, current_price: native.price_index },
      cohort: { actual_formula: records.get(`D${rows.treasury_cohorts_pct_initial_gdp_0}`).formula,
        expected: native.treasury_cohorts_pct_initial_gdp[0] },
    }));
    assert.equal(records.get(`D${rows.quarter_index}`).value, native.quarter_index,
      'Full-state initialization must preserve the absolute native checkpoint quarter, not cold Q0');
  }
  const { applyFixture: applyCheckpoint, writeInputs: restoreCheckpoint } = vm.runInNewContext(`${source.slice(start, end)}\n({applyFixture, writeInputs})`, { assert });
  const lendingCheckpoint = fixtures.flatMap(fixture => fixture.quarters).find(row => row.state.outstanding_liquidity_pct_initial_gdp > 0)?.state;
  assert.ok(lendingCheckpoint, 'Current late references must exercise a real positive-loan checkpoint');
  for (const state of [...fixtures.map(fixture => fixture.initial_state), lendingCheckpoint]) {
    const edits = checkpointEdits(economy, rows, state);
    assert.equal(edits.length, Object.keys(flattenState(state)).length, 'Initialize every scalar, all five prices and every principal/tag/bill cohort');
    const before = new Map([...records].map(([ref, record]) => [ref, { ...record }]));
    const saved = applyCheckpoint(edits);
    assert.equal(verifyTrace(`native Q${state.quarter_index} checkpoint`, [state]), 0, 'Full checkpoint equality, including loans, original bases and prior guidance');
    restoreCheckpoint(saved.map(([target, ref, value, formula]) => [target, ref, formula || value, Boolean(formula)]));
    for (const [ref, original] of before) {
      const actual = records.get(ref);
      assert.equal(actual.formula || actual.value, original.formula || original.value, `Restore every overwritten original formula/value exactly: ${ref}`);
    }
  }
  const beforeInvalid = JSON.stringify([...records]);
  for (const key of ['quarter_index', 'price_history', 'initial_actual_output_index', 'initial_price_index',
    'guidance_active', 'guidance_reference_inflation_pct', 'outstanding_liquidity_pct_initial_gdp',
    'treasury_cohorts_pct_initial_gdp', 'sterilized_treasury_cohorts_pct_initial_gdp', 'bill_cohorts_pct_initial_gdp']) {
    const incomplete = { ...native }; delete incomplete[key];
    assert.throws(() => checkpointEdits(economy, rows, incomplete), /Full-state checkpoint fields/, `Reject missing ${key}`);
  }
  assert.throws(() => checkpointEdits(economy, rows, { ...native, price_history: native.price_history.slice(1) }), /Native array schema/);
  assert.throws(() => checkpointEdits(economy, rows, { ...native, price_index: Infinity }), /Invalid checkpoint type/);
  assert.throws(() => checkpointEdits(economy, rows, { ...native, guidance_active: 1 }), /Invalid checkpoint type/);
  assert.throws(() => checkpointEdits(economy, { ...rows, initial_price_index: undefined }, native), /Unmapped checkpoint field/);
  assert.equal(JSON.stringify([...records]), beforeInvalid, 'Malformed checkpoint inputs never mutate cells');

  const quarterEnd = source.indexOf('  if (q === 0) {', coldStart), quarters = [];
  vm.runInNewContext(`${source.slice(coldStart, quarterEnd)}\n}`, {
    column: columnName, f: (col, key) => `${col}${rows[key]}`, economy,
    cell: (_, ref, value, formula) => quarters.push({ ref, value, formula }),
  });
  assert.equal(quarters.length, 49);
  assert.equal(quarters[0].value, 0, 'Cold initialization remains Q0');
  for (let q = 1; q <= 48; q++) {
    assert.equal(quarters[q].value, `=${columnName(q + 3)}${rows.quarter_index}+1`, 'Every transition advances its actual prior quarter');
    assert.equal(quarters[q].formula, true, 'Quarter continuity is calculated, not a relative literal');
  }
  const historyStart = source.indexOf('  for (let age = 0; age < 4;', coldEnd), historyEnd = source.indexOf("  put('annualized_quarterly_inflation_pct'", historyStart);
  for (let q = 1; q <= 4; q++) {
    const emitted = new Map();
    vm.runInNewContext(source.slice(historyStart, historyEnd), {
      prev: key => `${columnName(q + 3)}${rows[key]}`, s: key => `${columnName(q + 4)}${rows[key]}`,
      put: (key, formula) => emitted.set(key, formula),
    });
    for (let age = 0; age < 4; age++) assert.equal(emitted.get(`price_h${age}`), `${columnName(q + 3)}${rows[`price_h${age + 1}`]}`, 'Shift actual retained prices, never synthesize prehistory');
    assert.equal(emitted.get('four_quarter_inflation_pct'), `100*(${columnName(q + 4)}${rows.price_h4}/${columnName(q + 4)}${rows.price_h0}-1)`);
    for (const fixture of fixtures) {
      const state = fixture.quarters[q - 1].state;
      assert.equal(state.price_history[0], fixture.initial_state.price_history[q], 'The first four denominators come from the checkpoint');
      assert.ok(Math.abs(100 * (state.price_index / fixture.initial_state.price_history[q] - 1) - state.four_quarter_inflation_pct) < 1e-7);
    }
  }

  const nominalStart = source.indexOf('const nominalKeys = '), nominalEnd = source.indexOf('const out = ', nominalStart);
  const { nominalKeys, nominalRatio, shockDefault } = vm.runInNewContext(`${source.slice(nominalStart, nominalEnd)}\n({nominalKeys, nominalRatio, shockDefault})`, { assert });
  const idsStart = source.indexOf('const ids = '), idsEnd = source.indexOf('const cases = ', idsStart);
  const { ids } = vm.runInNewContext(`${source.slice(idsStart, idsEnd)}\n({ids})`);
  const shockStart = source.indexOf('const shockKeys = '), shockEnd = source.indexOf('const shockRows = ', shockStart);
  const { shockKeys } = vm.runInNewContext(`${source.slice(shockStart, shockEnd)}\n({shockKeys})`);
  const policyStart = source.indexOf('const policyRows = '), policyEnd = source.indexOf(';', policyStart) + 1;
  const { policyRows } = vm.runInNewContext(`${source.slice(policyStart, policyEnd)}\n({policyRows})`);
  const plotStart = source.indexOf('const plotKeys = '), plotEnd = source.indexOf('lab.getRange(', plotStart);
  const { plotKeys } = vm.runInNewContext(`${source.slice(plotStart, plotEnd)}\n({plotKeys})`);
  const fixtureStart = source.indexOf('const checkpointFixtureEdits = '), fixtureEnd = source.indexOf("if (buildPhase !== 'main') {", fixtureStart);
  const lab = { name: 'Policy Lab' }, policy = { name: 'Policy' }, shocks = { name: 'Shocks' };
  const shockRows = new Map(shockKeys.map((key, i) => [key, 6 + i * (ids.length + 2)]));
  const { checkpointFixtureEdits } = vm.runInNewContext(`${source.slice(fixtureStart, fixtureEnd)}\n({checkpointFixtureEdits})`, {
    assert, ids, checkpointEdits, economy, R: rows, lab, policy, shocks, column: columnName,
    shockKeys, shockRows, policyRows, nominalKeys, nominalRatio, shockDefault, plotKeys,
  });
  for (const fixture of fixtures) {
    const edits = checkpointFixtureEdits(fixture), inputs = new Map(edits.map(([sheet, ref, value]) => [`${sheet.name}!${ref}`, value]));
    assert.equal(inputs.size, edits.length, 'Each checkpoint fixture captures/writes every target exactly once');
    assert.equal(inputs.get('Policy Lab!C5'), fixture.quarters.length, 'Summary stops at the segment horizon');
    assert.equal(inputs.get('Policy Lab!B5'), 'Quarter offset from checkpoint', 'Selector offset is not mislabeled as an absolute quarter');
    assert.match(inputs.get('Policy Lab!B8'), /Not full 240-quarter parity/);
    const labels = Array.from({ length: 49 }, (_, q) => inputs.get(`Policy Lab!B${q + 58}`));
    for (let q = 0; q <= fixture.quarters.length; q++) assert.equal(labels[q], `Q${fixture.start_quarter + q}`, 'Count the actual absolute-quarter calendar');
    verifySummaryHorizon(labels, fixture.quarters.length);
    const savedCalendar = applyFixture(Array.from(mainLabels.keys(), ref => [sheet, ref, inputs.get(`Policy Lab!${ref}`)]));
    verifySummaryHorizon(Array.from(mainLabels.keys(), ref => originals.get(ref).value), fixture.quarters.length);
    writeInputs(savedCalendar.map(([target, ref, value, formula]) => [target, ref, formula || value, Boolean(formula)]));
    assert.deepEqual(Array.from(mainLabels.keys(), ref => originals.get(ref).value), Array.from(mainLabels.values()), 'Restore the exact main calendar after every checkpoint');
    verifySummaryHorizon(Array.from(mainLabels.keys(), ref => originals.get(ref).value), 48);
    for (let q = 0; q < 48; q++) {
      const row = fixture.quarters[q], col = columnName(q + 5), caseIndex = ids.indexOf(fixture.scenario.id);
      for (const key of shockKeys) assert.equal(inputs.get(`Shocks!${col}${shockRows.get(key) + caseIndex + 1}`), row?.shock[key] ?? shockDefault(key), 'Actual initial-GDP shocks or cleared suffix defaults');
      for (const [key, policyRow] of Object.entries(policyRows)) {
        const actual = inputs.get(`Policy!${col}${policyRow}`);
        if (row && Object.hasOwn(row.policy, key)) {
          const expected = row.policy[key];
          assert.ok(Math.abs((nominalKeys.has(key) ? actual * nominalRatio(q ? fixture.quarters[q - 1].state : fixture.initial_state) : actual) - expected) < 1e-7, 'Offers use prior meeting GDP, not rebased or current ending GDP');
        } else assert.equal(actual, ['reinvest_principal', 'maintain_ample_reserves'].includes(key) ? true : key === 'sterilize_purchases' ? false : ['asset_flow_request_pct_initial_gdp', 'liquidity_request_pct_initial_gdp'].includes(key) ? 0 : null, 'Unused controls are cleared to existing native defaults');
      }
      assert.equal(inputs.get(`Policy!${col}4`), row ? `Q${fixture.start_quarter + q + 1}` : null);
    }
    for (let q = fixture.quarters.length + 1; q <= 48; q++) {
      assert.equal(inputs.get(`Policy Lab!B${q + 58}`), null, 'No unvalidated suffix chart labels');
      for (let i = 0; i < plotKeys.length; i++) assert.equal(inputs.get(`Policy Lab!${columnName(i + 3)}${q + 58}`), null, 'No unvalidated suffix chart results');
    }
  }
  assert.throws(() => checkpointFixtureEdits({ ...fixtures[0], end_quarter: 169 }), /Checkpoint segment horizon/);
  assert.throws(() => checkpointFixtureEdits({ ...fixtures[0], scenario: { id: 'missing' } }), /Checkpoint segment horizon/);
  const saveLoopStart = source.indexOf('for (const i of phaseCheckpoints[buildPhase])'), saveLoopEnd = source.indexOf('await fs.writeFile(new URL(`workbook-parity-', saveLoopStart);
  const saveLoop = source.slice(saveLoopStart, saveLoopEnd);
  assert.ok(saveLoop.indexOf('await snapshot.save(') < saveLoop.indexOf('writeInputs(saved.map'), 'Persist each disposable fixture before restoration');
  assert.ok(saveLoop.includes('writeInputs(saved.map(([sheet, ref, value, formula]) => [sheet, ref, formula || value, Boolean(formula)]))'), 'The actual fixture loop restores formulas rather than their stale cached values');
  assert.ok(saveLoop.indexOf('writeInputs(saved.map') < saveLoop.indexOf('restored ${fixture.name}'), 'Verify cold parity again only after restoration');
  console.log('PASS: full-state checkpoint input contract and exact first-column restoration (simulated cells; not segment formula parity)');
  console.log('PASS: rejected missing/type/map mutations, absolute-quarter/retained-price writers, sourced fixture inputs and cleared short suffix (VM/static evidence)');
}
