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
assert.equal(Object.values(inventory.data_validations).reduce((count, values) => count + Object.keys(values).length, 0), 5);
const temporary = await fs.mkdtemp(path.join(path.dirname(process.argv[3]), 'upstream77-human-'));
try {
  const changed = path.join(temporary, 'builder.mjs');
  await fs.writeFile(changed, text.replace(humanLine, "const human = key => 'upstream77-' + key;"));
  const observed = await authoredInventory(changed, references, rows);
  assert.equal(observed.literal_inputs.Assumptions.B6, 'upstream77-' + source.parameters[0].key,
    'The actual human declaration runs in the pure VM; neither a host stub nor copied transform may replace it');
} finally { await fs.rm(temporary, { recursive: true }); }
console.log('PASS: upstream77 actual pure inventory binds parameter metadata, cold/late decision headers, five rules and source-emitted output fields; actual human declaration is live');
