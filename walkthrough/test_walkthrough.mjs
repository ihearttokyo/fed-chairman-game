// Dependency-free contracts; synthetic data is not native-engine evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
const root = path.dirname(fileURLToPath(import.meta.url));
const app = fs.readFileSync(path.join(root, 'dist/app.js'), 'utf8');
const html = fs.readFileSync(path.join(root, 'dist/index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'dist/style.css'), 'utf8');
const pure = { module: { exports: {} }, Intl };
vm.runInNewContext(app, pure);
const api = pure.module.exports;
function fixture() {
  const before = { inflation: 4, unemployment: 5, output_gap: -1, credibility: .25, support: 70 };
  return { schema_version: 1, source_commit: 'a'.repeat(40), model_digest: 'b'.repeat(64), lessons: Array.from({ length: 8 }, (_, i) => ({
    id: `lesson-${i}`, title: `Synthetic lesson ${i}`, task: 'Compare synthetic paths', scenario: 'synthetic', seed: 1, mode: 'test', before: { ...before },
    options: ['reference', 'alternative'].map((id, j) => ({ id, label: id, action: 'test only', policy: {}, notes: 'Synthetic test input',
      path: Array.from({ length: 8 }, (_, q) => ({ ...before, quarter: q + 1, inflation: 4 - q * .1 - j * .2, unemployment: 5 + j * .1, uncovered_funding: 0 })) })),
    takeaway: 'Synthetic only', native_steps: ['Open the native app'], source_paths: ['game/model/economy.gd']
  })) };
}
test('percentages, credibility fractions and public-support points are distinct', () => {
  assert.equal(api.formatValue(2, 'inflation'), '2%');
  assert.equal(api.formatValue(.72, 'credibility'), '72 /100');
  assert.equal(api.formatValue(.25, 'credibility'), '25 /100');
  assert.equal(api.formatValue(70, 'support'), '70 /100');
  assert.equal(api.formatValue(.1, 'support'), '0.1 /100');
  assert.equal(api.formatValue(-.1, 'support', true), '-0.1 index points');
  assert.equal(api.formatValue(-.001, 'credibility', true), '-0.1 index points');
  assert.equal(api.formatValue(.1, 'support', true), '+0.1 index points');
  assert.equal(api.formatValue(100, 'support'), '100 /100');
  assert.equal(api.formatValue(-.2, 'unemployment', true), '-0.2 pp');
  assert.equal(api.formatValue(0, 'assets'), '0% initial GDP');
  for (const value of [undefined, null, NaN, Infinity, '2']) assert.equal(api.formatValue(value, 'inflation'), 'Unavailable');
  assert.equal(api.difference(null, 0), null);
  assert.equal(api.formatValue(api.difference(2, 2), 'inflation', true), '0 pp');
  assert.equal(api.formatValue(.0000001, 'inflation', true), '+1E-7 pp');
  assert.equal(api.formatValue(.000001, 'assets'), '1E-6% initial GDP');
});
test('negative and large values preserve signs, field scales and ledger units', () => {
  assert.equal(api.formatValue(-12.345, 'inflation'), '-12.345%');
  assert.equal(api.formatValue(-1234567.89, 'output_gap'), '-1,234,567.89%');
  assert.equal(api.formatValue(1234567.89, 'assets'), '1,234,567.89% initial GDP');
  assert.equal(api.formatValue(-12.5, 'loans'), '-12.5% initial GDP');
  assert.equal(api.formatValue(20, 'uncovered_funding'), '20% initial GDP');
  assert.equal(api.formatValue(-.1, 'uncovered_funding', true), '-0.1 pp of initial GDP');
  assert.equal(api.formatValue(1234567.89, 'loans', true), '+1,234,567.89 pp of initial GDP');
  assert.equal(api.formatValue(-99.999, 'support', true), '-99.999 index points');
  assert.equal(api.formatValue(-1, 'credibility', true), '-100 index points');
  assert.equal(api.formatValue(-0, 'support', true), '0 index points');
});
test('credibility validates 0–1 while support validates 0–100 without normalization', () => {
  for (const [field, valid, invalid] of [
    ['credibility', [0, .25, 1], [-.001, 1.001, 100, null, Infinity, '0.25']],
    ['support', [0, .1, 70, 100], [-.1, 100.1, 1000000, null, Infinity, '70']]
  ]) {
    for (const value of valid) {
      const d = fixture(); d.lessons[0].before[field] = value;
      d.lessons[0].options[0].path[0][field] = value;
      api.validateDataset(d);
      assert.equal(d.lessons[0].before[field], value);
      assert.equal(d.lessons[0].options[0].path[0][field], value);
    }
    for (const value of invalid) for (const location of ['before', 'path']) {
      const d = fixture();
      (location === 'before' ? d.lessons[0].before : d.lessons[0].options[0].path[0])[field] = value;
      assert.throws(() => api.validateDataset(d), `${field} ${location} rejects ${value}`);
    }
  }
});
test('complete matched eight-quarter paths required; ledger extras optional', () => {
  const d = fixture(); assert.equal(api.validateDataset(d), d);
  assert.equal(api.formatValue(d.lessons[0].options[0].path[0].assets, 'assets'), 'Unavailable');
  for (const edit of [
    d => d.schema_version = 99, d => d.lessons.pop(), d => d.lessons[0].options[1].path.pop(),
    d => d.lessons[0].options[1].path[0].inflation = null,
    d => d.lessons[0].options[1].path[0].unemployment = Infinity,
    d => d.lessons[0].options[1].path[0].credibility = 2,
    d => d.lessons[0].options[1].path[0].assets = 'unknown',
    d => d.lessons[0].options[1].path[1].quarter = 5,
    d => d.lessons[0].options[1].path.forEach(row => row.quarter += 1),
    d => d.lessons[1].id = d.lessons[0].id,
    d => d.lessons[0].options[1].id = 'reference',
    d => d.lessons[0].native_steps = [], d => d.lessons[0].source_paths = ['../private']
  ]) { const broken = fixture(); edit(broken); assert.throws(() => api.validateDataset(broken)); }
});
test('lesson-specific metric defaults teach the relevant mechanism', () => {
  for (const [title, expected] of [
    ['Rates', ['inflation', 'unemployment']], ['Guidance', ['inflation', 'unemployment']],
    ['Liquidity', ['uncovered_funding', 'loans']], ['Portfolio', ['assets', 'loans']],
    ['Credibility', ['credibility', 'support']], ['Recovery', ['output_gap', 'unemployment']],
    ['Committee', ['inflation', 'unemployment']], ['Bank workout borrowing costs', ['loans', 'uncovered_funding']]
  ]) assert.deepEqual(Array.from(api.defaultMetrics({ title })), expected, title);
});
test('funding peak includes early need and refuses incomplete observations', () => {
  const d = fixture(), lesson = d.lessons[0], p = lesson.options[0].path;
  p[0].uncovered_funding = 7; p[3].uncovered_funding = 12;
  assert.equal(p[7].uncovered_funding, 0); assert.equal(api.fundingPeak(p), 12);
  assert.equal(api.fundingRelevant(lesson, ['inflation', 'unemployment']), true);
  assert.equal(api.fundingPeak(p.slice(1)), null);
  delete p[2].uncovered_funding; assert.equal(api.fundingPeak(p), null);
});
test('first-quarter borrowing costs use contractual context, payment flows and separate unpaid claims', () => {
  const option = fixture().lessons[0].options[0];
  option.ledger = {};
  option.ledger.credit_contexts = [{ annual_rate_pct: -1.25, quarter_index: 1 }, { annual_rate_pct: 99 }];
  option.ledger.credit_results = [{ paid_positive: .2, paid_negative: .05 }];
  option.ledger.credit_states = [{ payable: .3, receivable: .1 }];
  const actual = api.firstCreditSettlement(option);
  assert.equal(actual.apr, -1.25); assert.equal(actual.paidToFed, .2); assert.equal(actual.paidToBank, .05);
  assert.equal(actual.unpaidToFed, .3); assert.equal(actual.unpaidFromFed, .1);
  option.ledger.credit_contexts[0].quarter_index = 2; assert.equal(api.firstCreditSettlement(option).apr, null);
  option.ledger.credit_results[0].paid_positive = -1; assert.equal(api.firstCreditSettlement(option).paidToFed, null);
  option.ledger.credit_states[0].payable = '0.3'; assert.equal(api.firstCreditSettlement(option).unpaidToFed, null);
  assert.ok(Object.values(api.firstCreditSettlement({ path: option.path })).every(value => value === null));
});
test('pinned source links reject unsafe paths and atlas targets exist', () => {
  const commit = 'a'.repeat(40);
  assert.equal(api.sourceURL(commit, 'game/model/economy.gd'), `https://github.com/ihearttokyo/fed-chairman-game/blob/${commit}/game/model/economy.gd`);
  for (const p of ['../secrets', '/etc/passwd', 'https://host/a', 'game//model', 'game/./file', 'x?y', 'x#z']) assert.equal(api.sourceURL(commit, p), null);
  assert.equal(api.sourceURL('main', 'game/README.md'), null);
  for (const [, p] of api.ATLAS) assert.ok(fs.existsSync(path.join(root, '..', p)), p);
});
test('local progress is provenance-bound and corrupt choices are discarded', () => {
  const d = fixture(), saved = { source_commit: d.source_commit, model_digest: d.model_digest, index: 2, choices: { 'lesson-0': 'alternative', 'lesson-1': 'invalid' } };
  const restored = api.parseProgress(JSON.stringify(saved), d);
  assert.equal(restored.index, 2); assert.equal(restored.choices['lesson-0'], 'alternative'); assert.equal(restored.choices['lesson-1'], undefined);
  for (const raw of ['bad JSON', null, JSON.stringify({ ...saved, index: -1 }), JSON.stringify({ ...saved, source_commit: 'changed' }), JSON.stringify({ ...saved, model_digest: 'changed' })]) {
    assert.equal(api.parseProgress(raw, d).index, 0); assert.equal(Object.keys(api.parseProgress(raw, d).choices).length, 0);
  }
});
test('a constant chart remains finite without changing its observations', () => {
  const values = [2, 2, 2], [lo, hi] = api.extent(values);
  assert.ok(lo < 2 && hi > 2); assert.deepEqual(values, [2, 2, 2]);
});
// A minimal DOM stand-in exercises wiring, not layout, rendering or accessibility APIs.
class Node {
  constructor(tag = 'div') { this.tagName = tag; this.children = []; this.attrs = {}; this.events = {}; this.hidden = false; this.disabled = false; this.classList = { add: () => {} }; this._text = ''; }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map(c => c.textContent).join(''); }
  setAttribute(key, value) { this.attrs[key] = String(value); }
  append(...nodes) { this.children.push(...nodes); }
  replaceChildren(...nodes) { this._text = ''; this.children = [...nodes]; }
  addEventListener(event, handler) { this.events[event] = handler; }
  focus() { this.focused = true; }
  click() { if (!this.disabled) this.events.click?.(); }
}
async function boot({ data = fixture(), failure, storageBlocked = false } = {}) {
  const nodes = new Map([...html.matchAll(/id="([^"]+)"/g)].map(m => [m[1], new Node()]));
  nodes.get('experience').hidden = true;
  const storage = new Map([['unrelated-native-key', 'keep']]);
  const requests = [];
  const context = {
    Intl, console, window: { matchMedia: () => ({ matches: false, addEventListener: () => {} }) },
    document: { getElementById: id => { assert.ok(nodes.has(id), `Missing HTML id: ${id}`); return nodes.get(id); }, createElement: tag => new Node(tag), createElementNS: (_, tag) => new Node(tag) },
    localStorage: {
      getItem: key => { if (storageBlocked) throw Error('blocked'); return storage.get(key) ?? null; },
      setItem: (key, value) => { if (storageBlocked) throw Error('blocked'); storage.set(key, value); },
      removeItem: key => { if (storageBlocked) throw Error('blocked'); storage.delete(key); }
    },
    fetch: async (...args) => { requests.push(args); if (failure) throw Error(failure); return { ok: true, json: async () => data }; }
  };
  vm.runInNewContext(app, context);
  await new Promise(resolve => setImmediate(resolve));
  return { nodes, storage, requests };
}
test('lesson selection, actual rows, native steps, navigation and scoped reset', async () => {
  const d = fixture(); d.lessons[0].options[1].label = '<script>not executable</script>';
  const { nodes: n, storage, requests } = await boot({ data: d });
  assert.equal(requests.length, 1); assert.equal(requests[0][0], 'lessons.json');
  assert.equal(n.get('lesson-nav').children.length, 8); assert.equal(n.get('results').hidden, true);
  assert.ok(n.get('native-steps').textContent.includes('native app'));
  assert.match(n.get('before').textContent, /25 \/100/);
  assert.match(n.get('before').textContent, /70 \/100/);
  assert.match(n.get('before').textContent, /0–100 index; no rescaling/);
  n.get('options').children[1].click();
  assert.equal(n.get('results').hidden, false); assert.equal(n.get('options').children[1].attrs['aria-pressed'], 'true');
  assert.ok(n.get('endpoints').textContent.includes('-0.2 pp')); assert.ok(n.get('data-table').textContent.includes('Unavailable'));
  assert.ok(n.get('data-table').textContent.includes('<script>not executable</script>'));
  assert.equal(n.get('chart').children[0].attrs.role, 'img');
  assert.equal(n.get('data-table').children.length, 8);
  n.get('next').click(); assert.equal(n.get('results').hidden, true); assert.equal(n.get('lesson-title').textContent, 'Synthetic lesson 1');
  n.get('back').click(); assert.equal(n.get('results').hidden, false);
  n.get('lesson-nav').children[7].children[0].click(); assert.equal(n.get('next').disabled, true);
  n.get('reset').click(); assert.equal(n.get('results').hidden, true); assert.equal(n.get('back').disabled, true);
  assert.equal(storage.get('unrelated-native-key'), 'keep'); assert.equal(storage.has(api.STORAGE_KEY), false);
});
test('selectors update both chart lanes and Q8 summary for any macro metric', async () => {
  const d = fixture(); d.lessons[0].title = 'Liquidity';
  const { nodes: n } = await boot({ data: d });
  assert.equal(n.get('metric-0').value, 'uncovered_funding'); assert.equal(n.get('metric-1').value, 'loans');
  assert.equal(n.get('metric-0').children.length, 8); assert.equal(n.get('metric-1').children.length, 8);
  n.get('options').children[1].click();
  assert.match(n.get('chart').textContent, /Uncovered funding/); assert.match(n.get('chart').textContent, /Unavailable/);
  for (const [key, label] of [['inflation', 'Inflation'], ['unemployment', 'Unemployment'], ['output_gap', 'Output gap'], ['uncovered_funding', 'Uncovered funding'], ['credibility', 'Credibility'], ['support', 'Public support'], ['assets', 'Assets'], ['loans', 'Loans']]) {
    n.get('metric-0').value = key; n.get('metric-0').events.change();
    assert.match(n.get('chart').textContent, new RegExp(label)); assert.match(n.get('endpoints').textContent, new RegExp(label));
    assert.doesNotMatch(JSON.stringify(n.get('chart').children), /NaN|Infinity/);
    if (['credibility', 'support'].includes(key)) assert.match(n.get('chart').textContent, /\/100 index/);
  }
  n.get('metric-0').value = 'credibility'; n.get('metric-0').events.change();
  assert.match(n.get('endpoints').textContent, /25 \/100/);
  n.get('next').click(); n.get('back').click(); assert.equal(n.get('metric-0').value, 'credibility');
  n.get('reset').click(); assert.equal(n.get('metric-0').value, 'uncovered_funding');
});
test('visible summary distinguishes zero ending funding from nonzero path peak', async () => {
  const d = fixture(), lesson = d.lessons[0]; lesson.title = 'Liquidity';
  lesson.options[0].path[0].uncovered_funding = 5;
  lesson.options[1].path[2].uncovered_funding = 9;
  const { nodes: n } = await boot({ data: d }); n.get('options').children[1].click();
  const summary = n.get('endpoints').textContent;
  assert.match(summary, /Peak uncovered funding, Q1–Q8/); assert.match(summary, /0% initial GDP/);
  assert.match(summary, /9% initial GDP/); assert.match(summary, /5% initial GDP/); assert.match(summary, /\+4 pp of initial GDP/);
});
test('workout has a visible actual export ledger and an honest missing-ledger fallback', async () => {
  const d = fixture(); d.lessons[0].title = 'Bank workout borrowing costs';
  let { nodes: n } = await boot({ data: d }); n.get('options').children[1].click();
  assert.equal(n.get('workout-ledger').hidden, false); assert.match(n.get('credit-summary').textContent, /Unavailable/);
  assert.equal(n.get('ledger-details').hidden, true);
  Object.assign(d.lessons[0].options[1], { ledger: {
    credit_contexts: [{ annual_rate_pct: -1.25 }], credit_results: [{ paid_positive: .2, paid_negative: .05 }],
    credit_states: [{ payable: .3, receivable: .1 }], bank_states: [{ cash: 7 }], bank_results: [{ settled: true }]
  } });
  ({ nodes: n } = await boot({ data: d })); n.get('ledger-quarter').value = '0'; n.get('options').children[1].click();
  assert.match(n.get('credit-summary').textContent, /Exported settlement, Q1/);
  assert.match(n.get('credit-summary').textContent, /-1.25% APR/);
  assert.match(n.get('credit-summary').textContent, /0.2% initial GDP/);
  assert.match(n.get('credit-summary').textContent, /0.05% initial GDP/);
  assert.match(n.get('credit-summary').textContent, /0.3% initial GDP/);
  assert.match(n.get('credit-summary').textContent, /0.1% initial GDP/);
  assert.equal(n.get('ledger-details').hidden, false); assert.match(n.get('ledger-raw').textContent, /bank_states/);
});
test('unavailable or invalid datasets expose no fabricated results', async () => {
  for (const options of [{ failure: 'Local file blocked' }, { data: { lessons: [] } }]) {
    const { nodes } = await boot(options);
    assert.equal(nodes.get('experience').hidden, true);
    assert.match(nodes.get('status').textContent, /No outcomes have been substituted/);
  }
});
test('storage refusal still allows in-memory policy choices', async () => {
  const { nodes } = await boot({ storageBlocked: true });
  nodes.get('options').children[1].click(); assert.equal(nodes.get('results').hidden, false);
  assert.match(nodes.get('storage-note').textContent, /only for this open page/);
});
test('static accessibility, privacy and dependency contracts', () => {
  assert.match(html, /Precomputed native-engine rehearsal/); assert.match(html, /Not the live game or a full simulator/);
  assert.match(html, /Download native Alpha 620/); assert.match(html, /Public project page/);
  assert.match(html, /href="https:\/\/github.com\/ihearttokyo\/fed-chairman-game\/releases\/tag\/v0\.1\.0-alpha\.620"/);
  assert.match(html, /href="https:\/\/the-chair\.jaymoney\.chatgpt\.site\/">Public project page/);
  assert.match(html, /Source repository/);
  assert.doesNotMatch(html + app, /raw export units|Credibility and support are unitless indices from 0 to 1/);
  assert.match(html, /role="status"/); assert.match(html, /Skip to decision desk/);
  assert.match(html, /for="metric-0"/); assert.match(html, /for="metric-1"/);
  assert.match(html, /Inspect all eight quarters of macro data/);
  assert.match(html, /<details/); assert.doesNotMatch(html, /\son\w+=|<iframe|<canvas|https?:[^"\s]+\.(js|css)/i);
  assert.match(css, /prefers-reduced-motion/); assert.match(css, /forced-colors/); assert.match(css, /focus-visible/);
  assert.doesNotMatch(app, /innerHTML|outerHTML|eval\(|setInterval|setTimeout|localStorage\.clear|sendBeacon|WebSocket/);
  assert.equal((app.match(/await fetch\(/g) || []).length, 1);
});
const dataPath = path.join(root, 'dist/lessons.json');
test('fixture-owner dataset conforms when available (no fixture mutation)', { skip: !fs.existsSync(dataPath) && 'Fixture owner has not supplied lessons.json' }, () => {
  const data = api.validateDataset(JSON.parse(fs.readFileSync(dataPath, 'utf8')));
  for (const lesson of data.lessons) for (const p of lesson.source_paths) assert.ok(fs.existsSync(path.join(root, '..', p)), p);
});

test('private same-origin lesson requests retain the owner session without cross-origin forwarding', () => {
  assert.ok(app.includes("fetch('lessons.json', { cache: 'no-store', credentials: 'same-origin' })"));
  assert.ok(!app.includes("credentials: 'include'"));
});

test('later workout settlement selects its own APR without rewriting path data', () => {
 const o=fixture().lessons[0].options[0]; o.ledger={credit_contexts:[{annual_rate_pct:2},{annual_rate_pct:-.75}]};
 assert.equal(api.firstCreditSettlement(o,1).apr,-.75);
 assert.equal(api.firstCreditSettlement(o,8).apr,null);
});
