import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export async function authoredInventory(builder, references, rowMap) {
  const bytes = await fs.readFile(builder), text = bytes.toString('utf8');
  const slice = (start, end) => {
    const first = text.indexOf(start), last = text.indexOf(end, first + start.length);
    assert.ok(first >= 0 && last > first, `Authored inventory boundary: ${start}`);
    return text.slice(first, last);
  };
  const line = start => { const first = text.indexOf(start); assert.ok(first >= 0, `Authored inventory declaration: ${start}`); return text.slice(first, text.indexOf('\n', first)); };
  const ids = vm.runInNewContext(`${slice('const ids = ', 'const cases = ')}\nids`);
  const referenceBytes = await Promise.all(Array.from(ids, id => fs.readFile(new URL(`${id}.json`, references))));
  const cases = referenceBytes.map(bytes => JSON.parse(bytes));
  const formulas = {}, literals = {};
  const economy = { name: 'Economy' }, noStyle = { getRange: () => ({ format: {} }) };
  // Execute the existing authoring sinks without Workbook construction, calculation or XLSX input.
  const program = [
    slice('const arrayShapes = ', 'const out = '),
    slice('const column = ', 'const cell = '), line('const clamp = '), line('const parameterRow = '),
    slice('const p = ', 'const weightsRow = '), line('const weightsRow = '),
    slice('const initialParameter = ', 'const shockKeys = '),
    slice('const shockKeys = ', 'const shockNoteRow = '),
    slice('const R = ', 'const sourceStart = '), line('const sourceStart = '),
    slice('const f = ', 'for (const [key, row] of Object.entries(R)) cell(economy,'),
    slice('for (let q = 0; q <= 48; q++) {\n  const col = column(q + 4);\n  for (const [label, key]', "if (buildPhase === 'main') await fs.writeFile"),
    '\n({ rows: R, stateFields: Object.keys(flattenState(source.initial_state)) })',
  ].join('\n');
  const emitted = vm.runInNewContext(program, {
    assert, cases, source: cases[0], economy, assumptions: noStyle, shocks: noStyle, input: () => {},
    headers: () => {}, human: key => key, C: { pale: '' },
    cell: (sheet, address, value, formula = false) => {
      if (sheet !== economy) return;
      if (formula) { formulas[address] = value; delete literals[address]; }
      else { literals[address] = value; delete formulas[address]; }
    },
  }, { timeout: 10000 });
  assert.deepEqual(JSON.parse(JSON.stringify(emitted.rows)), rowMap, 'Authored inventory row map differs from builder output');
  const required = { ...formulas, ...Object.fromEntries(Object.keys(literals).map(address => [address, null])) };
  for (const field of emitted.stateFields) {
    assert.ok(Number.isInteger(rowMap[field]), `Authored inventory missing state field: ${field}`);
    for (let q = 0; q <= 48; q++) {
      let n = q + 4, col = '';
      while (n) { col = String.fromCharCode(65 + (n - 1) % 26) + col; n = Math.floor((n - 1) / 26); }
      const address = `${col}${rowMap[field]}`;
      assert.ok(Object.hasOwn(formulas, address) || Object.hasOwn(literals, address), `Authored inventory missing emission: ${address}`);
      required[address] = Object.hasOwn(formulas, address) ? formulas[address] : null;
    }
  }
  return { schema_version: 1, builder_sha256: hash(bytes), generator_sha256: hash(await fs.readFile(new URL(import.meta.url))), row_map_sha256: hash(JSON.stringify(rowMap)),
    reference_sha256: Object.fromEntries(Array.from(ids, (id, i) => [id, hash(referenceBytes[i])])),
    state_fields: Array.from(emitted.stateFields), formulas: required };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 5, 'usage: generate-formula-inventory references-directory row-map output');
  const [references, map, output] = process.argv.slice(2);
  const builder = new URL('./build-policy-lab.mjs', import.meta.url);
  const inventory = await authoredInventory(builder, pathToFileURL(`${references}/`), JSON.parse(await fs.readFile(map, 'utf8')));
  await fs.writeFile(output, JSON.stringify(inventory, null, 2) + '\n', { flag: 'wx' });
  console.log(`PASS: authored formula inventory ${Object.keys(inventory.formulas).length} state cells; no recalculation`);
}
