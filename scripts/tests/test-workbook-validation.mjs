import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

const source = await fs.readFile(new URL('../spreadsheet/build-policy-lab.mjs', import.meta.url), 'utf8');
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
