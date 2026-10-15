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
  const formulas = {}, literals = {}, upstream = { Assumptions: {}, Shocks: {}, Policy: {}, 'Policy Lab': {} };
  const typed = Object.fromEntries(Object.keys(upstream).map(name => [name, {}]));
  const validations = Object.fromEntries(Object.keys(upstream).map(name => [name, {}]));
  const styles = new Map(), numberFormats = new Set(['General']);
  const write = (sheet, address, value, formula = false) => {
    if (sheet.name === 'Economy') {
      if (formula) { formulas[address] = value; delete literals[address]; }
      else { literals[address] = value; delete formulas[address]; }
    } else if (formula) { upstream[sheet.name][address] = value; delete typed[sheet.name][address]; }
    else {
      delete upstream[sheet.name][address];
      assert.ok(value === null || ['boolean', 'number', 'string'].includes(typeof value), 'Scalar authored input');
      assert.ok(typeof value !== 'number' || Number.isFinite(value), 'Finite authored input');
      typed[sheet.name][address] = value;
    }
  };
  const addresses = ref => {
    const bounds = /^([A-Z]+)([1-9][0-9]*)(?::([A-Z]+)([1-9][0-9]*))?$/.exec(ref);
    assert.ok(bounds, `Authored inventory range: ${ref}`);
    const first = [...bounds[1]].reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0);
    const last = [...(bounds[3] ?? bounds[1])].reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0);
    assert.ok(last >= first && Number(bounds[4] ?? bounds[2]) >= Number(bounds[2]), 'Ordered authored range');
    return Array.from({ length: Number(bounds[4] ?? bounds[2]) - Number(bounds[2]) + 1 }, (_, r) =>
      Array.from({ length: last - first + 1 }, (_, c) => {
        let n = first + c, col = '';
        while (n) { col = String.fromCharCode(65 + (n - 1) % 26) + col; n = Math.floor((n - 1) / 26); }
        return `${col}${Number(bounds[2]) + r}`;
      }));
  };
  const sheet = name => ({ name, freezePanes: { freezeRows() {}, freezeColumns() {} }, getRange(ref) {
    const targets = addresses(ref), target = this;
    const format = properties => {
      for (const address of targets.flat()) {
        const key = `${name}!${address}`, before = styles.get(key) ?? {};
        styles.set(key, { font: { ...before.font, ...properties.font }, fill: properties.fill ?? before.fill });
        if (properties.fill === palette.amber && name !== 'Economy'
            && !Object.hasOwn(typed[name], address) && !Object.hasOwn(upstream[name], address)) typed[name][address] = null;
      }
    };
    const font = new Proxy({}, { set(_, key, value) { format({ font: { [key]: value } }); return true; } });
    const formatting = new Proxy({}, {
      get(_, key) { return key === 'font' ? font : undefined; },
      set(_, key, value) { if (key === 'font' || key === 'fill') format({ [key]: value }); return true; },
    });
    const record = (matrix, formula) => {
      // Values broadcast 1x1 in the installed public API; formulas require an exact matrix.
      const broadcast = !formula && matrix.length === 1 && matrix[0].length === 1;
      assert.ok(broadcast || matrix.length === targets.length, 'Authored inventory matrix rows');
      for (const [r, row] of targets.entries()) {
        assert.ok(broadcast || matrix[r].length === row.length, 'Authored inventory matrix columns');
        for (const [c, address] of row.entries()) write(target, address, matrix[broadcast ? 0 : r][broadcast ? 0 : c], formula);
      }
    };
    return { get format() { return formatting; }, set format(value) { format(value); },
      setNumberFormat(value) { numberFormats.add(value); }, set values(matrix) { record(matrix, false); },
      set formulas(matrix) { record(matrix, true); },
      set dataValidation(value) { validations[name][ref] = value; } };
  } });
  const economy = sheet('Economy'), assumptions = sheet('Assumptions'), shocks = sheet('Shocks'), policy = sheet('Policy'), lab = sheet('Policy Lab');
  const palette = vm.runInNewContext(line('const C = ') + '\nC');
  // Execute the existing authoring sinks without Workbook construction, calculation or XLSX input.
  const program = [
    slice('const arrayShapes = ', 'const out = '),
    slice('const column = ', 'const cell = '), line('const human = '), line('const clamp = '),
    line('const headers = '), line('const input = '),
    slice('for (const sheet of [lab, policy, assumptions, economy, shocks]) {', 'lab.tabColor = '),
    slice("cell(lab, 'B4', 'Case number');", '// Parameters have one editable value'), slice("assumptions.getRange('B5:F5').values", 'const p = '),
    slice('const p = ', 'const weightsRow = '), slice('const weightsRow = ', 'const initialParameter = '),
    slice('const initialParameter = ', 'const shockKeys = '),
    slice('const shockKeys = ', 'const R = '),
    slice('const R = ', 'const sourceStart = '), slice('const sourceStart = ', 'const f = '),
    slice('const f = ', 'for (const [key, row] of Object.entries(R)) cell(economy,'),
    slice('economy.getRange(`B100:AZ', "if (buildPhase === 'main') await fs.writeFile"),
    slice('// Player controls remain separate from the one calculation chain.', '// Compact output table and editable native charts'),
    slice('// Compact output table and editable native charts', 'const plotKeys = '),
    slice('const checkpointEdits = ', 'const human = '), line('const plotKeys = '),
    slice("lab.getRange('B57:K57').values", 'const chart = '), line("cell(lab, 'B54'"),
    slice("lab.getRange('E1:P106').format", 'workbook.recalculate();'),
    slice('const policyRows = ', "if (buildPhase === 'main') {"),
    slice('const checkpointFixtureEdits = ', "if (buildPhase !== 'main') {"),
    '\n({ rows: R, stateFields: Object.keys(flattenState(source.initial_state)), policyOutputs, endingStocks: Array.from(endingStocks), upstreamCacheLayout: {parameter_rows:Object.fromEntries(parameterRow), initial_parameter:initialParameter, initial_rows:Object.fromEntries(initialRows), shock_rows:Object.fromEntries(shockRows), case_stride:caseStride, source_start:sourceStart, shock_defaults:Object.fromEntries(shockKeys.map(key=>[key,shockDefault(key)]))}, summaryFields: Object.fromEntries(metrics.map(([field], i) => [`C${12 + i}`, field])), checkpointFixtureEdits })',
  ].join('\n');
  const emitted = vm.runInNewContext(program, {
    assert, ids, cases, source: cases[0], portfolio: JSON.parse(cases[0].portfolio_reference_json),
    portfolioHash: cases[0].portfolio_reference_sha256, economy, assumptions, shocks, policy, lab,
    C: palette, cell: write,
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
  const policyReferences = new Set([...Object.values(formulas), ...Object.values(upstream.Assumptions), ...Object.values(upstream.Shocks)]
    .flatMap(formula => Array.from(formula.matchAll(/'Policy'!\$?([A-Z]+)\$?([0-9]+)/g), match => match[1] + match[2])));
  const literalInputs = typed;
  assert.equal(Object.keys(upstream.Policy).length, 20 * 48 + 1, 'All authored Policy calculated outputs and case header');
  const checkpointBytes = await fs.readFile(new URL('late-checkpoints.json', references));
  const checkpoints = JSON.parse(checkpointBytes);
  assert.equal(checkpoints.length, 6, 'Six authored checkpoint input overlays');
  const checkpointInputs = await Promise.all(checkpoints.map(async fixture => {
    assert.match(fixture.name, /^late_(hold|responsive)_(120_168|168_216|216_240)$/, 'Fixed authored checkpoint name');
    const raw = await fs.readFile(new URL(`${fixture.name}.json`, references));
    assert.deepEqual(JSON.parse(raw), fixture, 'Checkpoint reference differs from builder fixture');
    const overlay = Object.fromEntries(Object.keys(literalInputs).map(name => [name, {}]));
    const edits = emitted.checkpointFixtureEdits(fixture);
    for (const [sheet, address, value] of edits) {
      if (Object.hasOwn(literalInputs[sheet.name] ?? {}, address) || Object.hasOwn(upstream[sheet.name] ?? {}, address)) overlay[sheet.name][address] = value;
    }
    return { name: fixture.name, reference_sha256: hash(raw), literals: overlay,
      boolean_literals: edits.filter(([, , value]) => typeof value === 'boolean').map(([sheet, address]) => `${sheet.name}!${address}`) };
  }));
  assert.ok(Object.keys(upstream.Assumptions).length > 0 && Object.keys(upstream.Shocks).length > 0, 'Require authored upstream formula emissions');
  const fontFillPairs = [...new Set([{}, ...styles.values()].map(({ font = {}, fill = null }) =>
    JSON.stringify([font.name ?? null, font.size ?? null, font.color ?? null, font.bold ?? false, fill])))].map(value => JSON.parse(value));
  return { display_styles: { font_fill_pairs: fontFillPairs, number_formats: [...numberFormats],
    boolean_literals: Object.entries({ Economy: literals, ...literalInputs }).flatMap(([name, values]) =>
      Object.entries(values).filter(([, value]) => typeof value === 'boolean').map(([address]) => `${name}!${address}`)) }, schema_version: 3, benchmark_labels: Array.from(upstream['Policy Lab'].E6.matchAll(/"((?:[^"]|"")*)"/g), match => match[1].replaceAll('""', '"')), summary_fields: emitted.summaryFields, policy_output_fields: Array.from(emitted.policyOutputs), ending_stock_fields: Array.from(emitted.endingStocks), data_validations: validations, literal_inputs: literalInputs, checkpoint_inputs: checkpointInputs, case_order: Array.from(ids), upstream_formulas: upstream, policy_input_addresses: Array.from(policyReferences).sort(), builder_sha256: hash(bytes), generator_sha256: hash(await fs.readFile(new URL(import.meta.url))), row_map_sha256: hash(JSON.stringify(rowMap)),
    reference_sha256: Object.fromEntries(Array.from(ids, (id, i) => [id, hash(referenceBytes[i])])),
    upstream_cache_layout: emitted.upstreamCacheLayout, state_fields: Array.from(emitted.stateFields), formulas: required };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 5, 'usage: generate-formula-inventory references-directory row-map output');
  const [references, map, output] = process.argv.slice(2);
  const builder = new URL('./build-policy-lab.mjs', import.meta.url);
  const inventory = await authoredInventory(builder, pathToFileURL(`${references}/`), JSON.parse(await fs.readFile(map, 'utf8')));
  await fs.writeFile(output, JSON.stringify(inventory, null, 2) + '\n', { flag: 'wx' });
  console.log(`PASS: authored formula inventory ${Object.keys(inventory.formulas).length} state cells; no recalculation`);
}
