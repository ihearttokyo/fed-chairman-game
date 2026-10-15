import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import { pathToFileURL } from 'node:url';
import { authoredInventory } from '../spreadsheet/generate-formula-inventory.mjs';

assert.equal(process.argv.length, 4, 'usage: upstream77-inventory references-directory row-map');
const references = pathToFileURL(`${process.argv[2]}/`), rows = JSON.parse(await fs.readFile(process.argv[3], 'utf8'));
const builder = new URL('../spreadsheet/build-policy-lab.mjs', import.meta.url);
const text = await fs.readFile(builder, 'utf8'), inventory = await authoredInventory(builder, references, rows);
const humanLine = text.split('\n').find(line => line.startsWith('const human = '));
const human = vm.runInNewContext(humanLine + '\nhuman');
const source = JSON.parse(await fs.readFile(new URL('base.json', references)));
const checkpoints = await Promise.all(inventory.checkpoint_inputs.map(async overlay =>
  [overlay, JSON.parse(await fs.readFile(new URL(`${overlay.name}.json`, references)))]));
for (const [i, record] of source.parameters.entries()) {
  const literals = inventory.literal_inputs.Assumptions, row = i + 6;
  for (const [column, expected] of [['B', human(record.key)], ['E', record.unit],
    ['F', record.classification.replaceAll('_', ' ')], ['H', record.description], ['J', record.source || null]]) {
    assert.equal(literals[`${column}${row}`], expected, `upstream77 authored metadata ${column}${row}`);
  }
}
for (const sheet of ['Policy', 'Shocks']) for (let q = 1; q <= 48; q++) {
  let n = q + 4, column = '';
  while (n) { column = String.fromCharCode(65 + (n - 1) % 26) + column; n = Math.floor((n - 1) / 26); }
  assert.equal(inventory.literal_inputs[sheet][`${column}4`], q);
  for (const [overlay, fixture] of checkpoints) {
    assert.equal(overlay.literals[sheet][`${column}4`], q <= fixture.quarters.length ? `Q${fixture.start_quarter + q}` : null);
  }
}
for (const overlay of inventory.checkpoint_inputs) for (const address of ['B5', 'B8', 'B9']) {
  assert.equal(typeof overlay.literals['Policy Lab'][address], 'string');
}
const first = text.indexOf('const endingStocks = '), last = text.indexOf('for (const [i, key] of policyOutputs.entries())', first);
const actual = vm.runInNewContext(text.slice(first, last) + '\n({policyOutputs, endingStocks: Array.from(endingStocks)})');
assert.deepEqual(inventory.policy_output_fields, Array.from(actual.policyOutputs));
assert.deepEqual(inventory.ending_stock_fields, Array.from(actual.endingStocks));
assert.equal(inventory.policy_output_fields.length, 20); assert.equal(inventory.ending_stock_fields.length, 5);
const paletteLine = text.split('\n').find(line => line.startsWith('const C = '));
const palette = vm.runInNewContext(paletteLine + '\nC');
assert.ok(inventory.display_styles.font_fill_pairs.some(([name, size, color, bold, fill]) =>
  name === 'Arial' && size === 10 && color === '#FFFFFF' && bold && fill === palette.navy));
assert.ok(inventory.display_styles.font_fill_pairs.some(([name, size, color, bold, fill]) =>
  name === 'Arial' && size === 10 && color === palette.blue && !bold && fill === palette.amber));
for (const [overlay, fixture] of checkpoints) {
  for (const [field, value] of Object.entries(fixture.initial_state)) if (typeof value === 'boolean') {
    assert.ok(overlay.boolean_literals.includes(`Economy!D${rows[field]}`), 'display105 actual checkpoint writer retains Boolean literals');
  }
}
assert.ok(inventory.display_styles.boolean_literals.includes('Policy!E12'));
const actualFormats = [...new Set(Array.from(text.matchAll(/\.setNumberFormat\('([^']+)'\)/g), match => match[1]))];
assert.deepEqual(new Set(inventory.display_styles.number_formats), new Set(['General', ...actualFormats]));
assert.equal(Object.values(inventory.data_validations).reduce((count, values) => count + Object.keys(values).length, 0), 5);
// meta89 expectations execute the actual layout declarations, never a duplicate field/row list.
const declaration = prefix => {
  const first = text.indexOf(prefix); assert.ok(first >= 0, prefix);
  return text.slice(first, text.indexOf('\n', first));
};
const cases = await Promise.all(inventory.case_order.map(async id => JSON.parse(await fs.readFile(new URL(`${id}.json`, references)))));
const aliasesStart = text.indexOf('const initialParameter = '), aliasesEnd = text.indexOf('const initialRows = ', aliasesStart);
const layoutSource = [declaration('const parameterRow = '), text.slice(aliasesStart, aliasesEnd),
  declaration('const weightsRow = '), declaration('const initialFields = '), declaration('const caseStride = '),
  declaration('let initialRow = '), declaration('const shockKeys = '), declaration('const shockDefault = '),
  '({parameterRow:Object.fromEntries(parameterRow), initialParameter, initialFields, caseStride, initialRow, shockKeys, shockDefault})'].join('\n');
const actualLayout = vm.runInNewContext(layoutSource, { source, cases });
const layout = JSON.parse(JSON.stringify(inventory.upstream_cache_layout));
assert.deepEqual(JSON.parse(JSON.stringify(actualLayout.parameterRow)), layout.parameter_rows);
assert.deepEqual(JSON.parse(JSON.stringify(actualLayout.initialParameter)), layout.initial_parameter);
assert.equal(layout.case_stride, actualLayout.caseStride);
assert.deepEqual(Object.keys(layout.initial_rows), Array.from(actualLayout.initialFields));
for (const [i, key] of Array.from(actualLayout.initialFields).entries()) assert.equal(layout.initial_rows[key], actualLayout.initialRow + i * actualLayout.caseStride);
const sourceStart = vm.runInNewContext(declaration('const sourceStart = ') + '\nsourceStart', {
  initialRow: actualLayout.initialRow + actualLayout.initialFields.length * actualLayout.caseStride,
});
assert.equal(layout.source_start, sourceStart);
for (const [i, key] of Array.from(actualLayout.shockKeys).entries()) {
  const row = vm.runInNewContext(declaration('  const key = shockKeys[i], row = ') + '\nrow', { i, shockKeys: actualLayout.shockKeys, caseStride: actualLayout.caseStride });
  assert.equal(layout.shock_rows[key], row); assert.equal(layout.shock_defaults[key], actualLayout.shockDefault(key));
}
for (const address of ['B2', 'B4', 'B6', 'J4', 'J11', 'B12', 'B17', 'F12', 'F14', 'F16', 'B54', 'B57', 'B58', 'B106']) {
  assert.equal(typeof inventory.literal_inputs['Policy Lab'][address], 'string', 'meta89 retain every source caption');
}
for (const [overlay, fixture] of checkpoints) for (let q = 0; q <= 48; q++) {
  assert.equal(overlay.literals['Policy Lab'][`B${58 + q}`], q <= fixture.quarters.length ? `Q${fixture.start_quarter + q}` : null);
  if (q > fixture.quarters.length) for (const column of 'CDEFGHIJK') assert.equal(overlay.literals['Policy Lab'][`${column}${58 + q}`], null);
}
const temporary = await fs.mkdtemp(path.join(path.dirname(process.argv[3]), 'upstream77-human-'));
try {
  const changed = path.join(temporary, 'builder.mjs');
  await fs.writeFile(changed, text.replace(humanLine, "const human = key => 'upstream77-' + key;").replace(paletteLine, paletteLine.replace(palette.ink, '#172635')));
  const observed = await authoredInventory(changed, references, rows);
  assert.ok(observed.display_styles.font_fill_pairs.some(([, , color]) => color === '#172635'), 'display105 executes the actual palette and format writes');
  assert.ok(!observed.display_styles.font_fill_pairs.some(([, , color]) => color === palette.ink));
  assert.equal(observed.literal_inputs.Assumptions.B6, 'upstream77-' + source.parameters[0].key,
    'The actual human declaration runs in the pure VM; neither a host stub nor copied transform may replace it');
} finally { await fs.rm(temporary, { recursive: true }); }
console.log('PASS: upstream77 actual pure inventory binds parameter metadata, cold/late decision headers, five rules and source-emitted output fields; actual human declaration is live');
console.log('PASS: meta89 actual-source layout bridge, complete Lab literals and checkpoint cleared-suffix overlays');

console.log('PASS: display105 source-emitted paint pairs and number formats; changed actual palette reaches the contract');
