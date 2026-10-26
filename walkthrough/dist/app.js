/* Static rehearsal UI. No economic equations, native saves or network services. */
(() => {
  'use strict';
  const REPO = 'https://github.com/ihearttokyo/fed-chairman-game';
  const STORAGE_KEY = 'the-chair-walkthrough-v1';
  const METRICS = [
    ['inflation', 'Inflation', '%'], ['unemployment', 'Unemployment', '%'],
    ['output_gap', 'Output gap', '%'], ['uncovered_funding', 'Uncovered funding', '% initial GDP'],
    ['credibility', 'Credibility', '0–1 index ×100'], ['support', 'Public support', '0–100 index; no rescaling'],
    ['assets', 'Assets', '% initial GDP'], ['loans', 'Loans', '% initial GDP']
  ];
  const ATLAS = [
    ['Rates & guidance', 'game/model/economy.gd', 'Transmission and expectations; authored equations, not estimated policy.'],
    ['Balance sheet', 'game/play/funding_plan.gd', 'Asset offers, runoff, reserves and sterilization.'],
    ['Secured lending', 'game/play/policy_docket.gd', 'Inspect the lending decision alongside other policy controls.'],
    ['Recovery', 'game/play/career.gd', 'Recovery and career continuity, not an instant reset.'],
    ['Credibility & support', 'game/model/economy.gd', 'Policy consistency and lived outcomes are different indices.'],
    ['Shocks', 'game/model/exogenous_shocks.json', 'Authored disturbances, not a historical event forecast.'],
    ['Staff vs full-information benchmark', 'game/play/policy_advice.gd', 'Public-data advice is not the full-information benchmark.'],
    ['Committee', 'game/play/committee_docket.gd', 'Competing priorities and conditional eight-quarter comparisons.'],
    ['Routine follow-up', 'game/play/routine_follow_up.gd', 'Bounded staff updates with explicit stop conditions.'],
    ['Objectives & scoring', 'game/play/objective_board.gd', 'Scenario-specific progress; not “higher is always better.”'],
    ['Bank workout', 'game/play/bank_workout_panel.gd', 'Separate cash, withdrawals, repayment and renewal.'],
    ['Priced quote', 'game/play/priced_credit_panel.gd', 'Borrowing-cost variant; requested policy and contractual APR differ.'],
    ['Music', 'game/play/music.gd', 'Native preference, separate from career saves.'],
    ['Accessibility & controls', 'game/play/help_guide.gd', 'Native Help topics and keyboard reading.'],
    ['Saves & replay', 'game/play/career.gd', 'Native career state stays outside this companion.']
  ];
  const finite = n => typeof n === 'number' && Number.isFinite(n);
  const indexMetric = key => key === 'credibility' || key === 'support';
  function formatValue(value, key, difference = false) {
    if (!finite(value)) return 'Unavailable';
    const scaled = key === 'credibility' ? value * 100 : value;
    const tiny = scaled !== 0 && Math.abs(scaled) < .0005;
    const number = new Intl.NumberFormat('en-US', { maximumFractionDigits: 3, notation: tiny ? 'scientific' : 'standard' }).format(Object.is(scaled, -0) ? 0 : scaled);
    const sign = difference && scaled > 0 ? '+' : '';
    const suffix = indexMetric(key) ? (difference ? ' index points' : ' /100') :
      ['inflation', 'unemployment', 'output_gap'].includes(key) ? (difference ? ' pp' : '%') :
      ['uncovered_funding', 'assets', 'loans'].includes(key) ? (difference ? ' pp of initial GDP' : '% initial GDP') : '';
    return sign + number + suffix;
  }
  function difference(chosen, reference) { return finite(chosen) && finite(reference) ? chosen - reference : null; }
  const OPTIONAL_LEDGERS = ['bank_states', 'credit_states', 'credit_results', 'bank_results', 'credit_contexts'];
  const lessonTopic = lesson => `${lesson.id || ''} ${lesson.title || ''} ${lesson.mode || ''}`.toLowerCase();
  const isWorkout = lesson => /workout|borrowing|priced.credit/.test(lessonTopic(lesson));
  function defaultMetrics(lesson) {
    const topic = lessonTopic(lesson);
    if (isWorkout(lesson)) return ['loans', 'uncovered_funding'];
    if (/portfolio|balance.sheet|assets|runoff/.test(topic)) return ['assets', 'loans'];
    if (/credibility|public.support/.test(topic)) return ['credibility', 'support'];
    if (/recovery|recover/.test(topic)) return ['output_gap', 'unemployment'];
    if (/liquid|funding|lending|bank.run/.test(topic)) return ['uncovered_funding', 'loans'];
    return ['inflation', 'unemployment'];
  }
  function fundingPeak(path) {
    return Array.isArray(path) && path.length === 8 && path.every(row => finite(row?.uncovered_funding)) ? Math.max(...path.map(row => row.uncovered_funding)) : null;
  }
  function fundingRelevant(lesson, metrics) {
    return isWorkout(lesson) || /liquid|funding|lending|recovery/.test(lessonTopic(lesson)) ||
      metrics.some(key => ['uncovered_funding', 'loans'].includes(key)) ||
      lesson.options.some(option => option.path.some(row => finite(row.uncovered_funding) && row.uncovered_funding > 0));
  }
  function firstCreditSettlement(option, offset = 0) {
    const ledger = option.ledger && typeof option.ledger === 'object' ? option.ledger : {};
    const first = key => Array.isArray(ledger[key]) ? ledger[key][offset] : null;
    const aligned = row => row && typeof row === 'object' &&
      (row.quarter_index == null || row.quarter_index === option.path?.[offset]?.quarter);
    const context = first('credit_contexts'), result = first('credit_results'), claims = first('credit_states');
    const read = (row, key, physical = false) => aligned(row) && finite(row[key]) && (!physical || row[key] >= 0) ? row[key] : null;
    return {
      apr: read(context, 'annual_rate_pct'),
      paidToFed: read(result, 'paid_positive', true), paidToBank: read(result, 'paid_negative', true),
      unpaidToFed: read(claims, 'payable', true), unpaidFromFed: read(claims, 'receivable', true)
    };
  }
  function sourceURL(commit, path) {
    if (!/^[a-f0-9]{7,40}$/i.test(commit) || typeof path !== 'string' ||
        !/^[a-zA-Z0-9_./-]+$/.test(path) || path.startsWith('/') || path.split('/').some(p => !p || p === '.' || p === '..')) return null;
    return `${REPO}/blob/${commit}/${path}`;
  }
  function validateDataset(data) {
    const fail = message => { throw new Error(message); };
    if (!data || ![1, '1', '1.0'].includes(data.schema_version)) fail('Unsupported or missing lesson schema.');
    if (!sourceURL(data.source_commit, 'game/model/economy.gd') || typeof data.model_digest !== 'string' || !data.model_digest.trim()) fail('Missing or invalid source provenance.');
    if (!Array.isArray(data.lessons) || data.lessons.length !== 8) fail('The walkthrough requires eight complete lessons.');
    const ids = new Set();
    for (const lesson of data.lessons) {
      if (!lesson || typeof lesson.id !== 'string' || !lesson.id || ids.has(lesson.id)) fail('Lesson IDs must be present and unique.');
      ids.add(lesson.id);
      for (const key of ['title', 'task', 'scenario', 'mode', 'takeaway']) if (typeof lesson[key] !== 'string' || !lesson[key].trim()) fail(`Lesson ${lesson.id} is missing ${key}.`);
      if (!finite(lesson.seed)) fail(`Lesson ${lesson.id} has no valid seed.`);
      const validStateValue = (v, key) => finite(v) &&
        (key === 'credibility' ? v >= 0 && v <= 1 : key === 'support' ? v >= 0 && v <= 100 : true);
      for (const key of ['inflation', 'unemployment', 'output_gap', 'credibility', 'support']) if (!validStateValue(lesson.before?.[key], key)) fail(`Lesson ${lesson.id} has invalid starting conditions.`);
      if (!Array.isArray(lesson.source_paths) || !lesson.source_paths.length || !lesson.source_paths.every(p => sourceURL(data.source_commit, p))) fail(`Lesson ${lesson.id} has invalid source links.`);
      if (!(typeof lesson.native_steps === 'string' && lesson.native_steps.trim()) && !(Array.isArray(lesson.native_steps) && lesson.native_steps.length && lesson.native_steps.every(s => typeof s === 'string' && s.trim()))) fail(`Lesson ${lesson.id} has no native instructions.`);
      if (!Array.isArray(lesson.options) || lesson.options.length < 2) fail(`Lesson ${lesson.id} needs a reference and a policy alternative.`);
      const optionIds = new Set();
      let quarters;
      for (const option of lesson.options) {
        if (!option || typeof option.id !== 'string' || !option.id || optionIds.has(option.id) || typeof option.label !== 'string' || !option.label.trim()) fail(`Lesson ${lesson.id} has invalid policy options.`);
        optionIds.add(option.id);
        if (!Array.isArray(option.path) || option.path.length !== 8) fail(`Lesson ${lesson.id} must have eight-quarter paths.`);
        for (let i = 0; i < 8; i++) {
          const row = option.path[i];
          if (!row || !Number.isInteger(row.quarter) || (i > 0 && row.quarter !== option.path[i - 1].quarter + 1)) fail(`Lesson ${lesson.id} has invalid quarter labels.`);
          for (const key of ['inflation', 'unemployment', 'output_gap', 'credibility', 'support']) if (!validStateValue(row[key], key)) fail(`Lesson ${lesson.id} contains missing or nonfinite outcomes.`);
          for (const key of ['uncovered_funding', 'assets', 'loans']) if (row[key] != null && !finite(row[key])) fail(`Lesson ${lesson.id} contains invalid ledger values.`);
        }
        const labels = option.path.map(row => row.quarter).join(',');
        if (quarters !== undefined && labels !== quarters) fail(`Lesson ${lesson.id} has unmatched comparison quarters.`);
        quarters = labels;
      }
    }
    return data;
  }
  function parseProgress(raw, data) {
    const empty = { index: 0, choices: {} };
    try {
      const saved = JSON.parse(raw);
      if (!saved || saved.source_commit !== data.source_commit || saved.model_digest !== data.model_digest || !Number.isInteger(saved.index) || saved.index < 0 || saved.index >= data.lessons.length) return empty;
      const choices = {};
      for (const lesson of data.lessons) if (lesson.options.some(o => o.id === saved.choices?.[lesson.id])) choices[lesson.id] = saved.choices[lesson.id];
      return { index: saved.index, choices };
    } catch { return empty; }
  }
  function extent(values) {
    const lo = Math.min(...values), hi = Math.max(...values);
    // A constant series needs a nonzero plotting range; this padding is not an observation.
    const pad = hi === lo ? Math.max(Math.abs(lo) * .05, .1) : (hi - lo) * .12;
    return [lo - pad, hi + pad];
  }
  const api = { formatValue, difference, sourceURL, validateDataset, parseProgress, extent, defaultMetrics, fundingPeak, fundingRelevant, firstCreditSettlement, ATLAS, STORAGE_KEY };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof document === 'undefined') return;

  const $ = id => document.getElementById(id);
  const element = (tag, text, attrs = {}) => {
    const node = document.createElement(tag);
    if (text != null) node.textContent = text;
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
    return node;
  };
  let data, state, selectedMetrics, storageAvailable = true;
  const metricChoices = new Map();
  function announce(text) { $('status').textContent = text; }
  function storageFailure() {
    storageAvailable = false;
    $('storage-note').textContent = 'Browser storage is unavailable. Choices last only for this open page; no cloud or native save is used.';
  }
  function persist() {
    if (!storageAvailable) return;
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...state, source_commit: data.source_commit, model_digest: data.model_digest })); } catch { storageFailure(); }
  }
  function addLink(parent, text, path) {
    const url = sourceURL(data.source_commit, path);
    if (url) parent.append(element('a', text, { href: url }));
  }
  function renderNav() {
    $('lesson-nav').replaceChildren();
    data.lessons.forEach((lesson, index) => {
      const li = element('li');
      const button = element('button', null, { type: 'button', 'aria-label': `Lesson ${index + 1}: ${lesson.title}${state.choices[lesson.id] ? ', policy chosen' : ''}` });
      if (index === state.index) button.setAttribute('aria-current', 'step');
      button.append(element('span', String(index + 1).padStart(2, '0'), { class: 'number' }));
      const text = element('span', lesson.title);
      if (state.choices[lesson.id]) text.append(element('span', 'Policy chosen', { class: 'visited' }));
      button.append(text);
      button.addEventListener('click', () => navigate(index));
      li.append(button); $('lesson-nav').append(li);
    });
  }
  function navigate(index) {
    state.index = index; persist(); renderLesson(); $('desk').focus();
    announce(`Lesson ${index + 1} of 8. ${data.lessons[index].title}`);
  }
  function renderLesson() {
    const lesson = data.lessons[state.index];
    renderNav();
    $('ledger-quarter').replaceChildren(...lesson.options[0].path.map((point, i) => element('option', `Q${point.quarter}`, { value: String(i) })));
    $('ledger-quarter').value = '1'; // First interest on newly advanced principal is visible at the next settlement.
    $('lesson-position').textContent = `Lesson ${state.index + 1} of 8`;
    $('lesson-title').textContent = lesson.title;
    $('task').textContent = lesson.task;
    $('reference-label').textContent = `Reference: ${lesson.options[0].label}. Compare, don’t rank.`;
    $('before').replaceChildren();
    for (const key of ['inflation', 'unemployment', 'output_gap', 'credibility', 'support']) {
      const metric = METRICS.find(m => m[0] === key), group = element('div');
      group.append(element('dt', metric[1]), element('dd', formatValue(lesson.before[key], key)));
      if (indexMetric(key)) group.append(element('small', key === 'credibility' ? '0–1 index ×100' : '0–100 index; no rescaling'));
      $('before').append(group);
    }
    selectedMetrics = metricChoices.get(lesson.id) || defaultMetrics(lesson);
    selectedMetrics.forEach((key, index) => { $(`metric-${index}`).value = key; });
    $('metric-note').textContent = /portfolio|balance.sheet|assets|runoff/.test(lessonTopic(lesson)) ? 'Reserves and duration are not in these exported macro series.' : 'Each lane has its own labelled scale. Select any exported macro metric.';
    $('options').replaceChildren(); $('policy-details').replaceChildren();
    for (const [index, option] of lesson.options.entries()) {
      const button = element('button', option.label, { type: 'button', 'aria-pressed': 'false', 'aria-controls': 'results' });
      if (index === 0) button.append(element('span', 'Reference path'));
      button.addEventListener('click', () => {
        state.choices[lesson.id] = option.id; persist(); renderResults(); renderNav();
        announce(`${option.label} selected. Eight exported quarters and differences from ${lesson.options[0].label} are shown.`);
      });
      $('options').append(button);
      $('policy-details').append(element('h4', option.label));
      for (const key of ['action', 'policy', 'notes']) if (option[key] != null) {
        $('policy-details').append(element('p', key === 'action' ? 'Action' : key === 'policy' ? 'Exported policy controls (raw keys and units)' : 'Notes'));
        $('policy-details').append(element('pre', typeof option[key] === 'string' ? option[key] : JSON.stringify(option[key], null, 2)));
      }
    }
    $('takeaway').textContent = lesson.takeaway;
    $('native-steps').replaceChildren();
    const steps = Array.isArray(lesson.native_steps) ? lesson.native_steps : [lesson.native_steps];
    for (const step of steps) $('native-steps').append(element('li', step));
    $('lesson-context').textContent = `Scenario: ${lesson.scenario}. Seed: ${lesson.seed}. Mode: ${lesson.mode}.`;
    $('lesson-sources').replaceChildren();
    for (const path of [...new Set([...lesson.source_paths, 'game/model/parameters.json', 'docs/MODEL_CONTRACT.md'])]) {
      const li = element('li'); addLink(li, path, path); $('lesson-sources').append(li);
    }
    $('provenance').replaceChildren();
    for (const [label, value] of [['Schema', data.schema_version], ['Source commit', data.source_commit], ['Model digest', data.model_digest]]) $('provenance').append(element('dt', label), element('dd', String(value)));
    $('back').disabled = state.index === 0; $('next').disabled = state.index === 7;
    $('progress').textContent = `${Object.keys(state.choices).length} of 8 lessons have a chosen policy`;
    renderResults();
  }
  function svgNode(tag, attrs = {}, text) {
    const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
    if (text != null) node.textContent = text;
    return node;
  }
  function drawChart(option, reference) {
    const names = selectedMetrics.map(key => METRICS.find(m => m[0] === key)[1]);
    const compact = window.matchMedia('(max-width:480px)').matches;
    const width = compact ? 360 : 660;
    const svg = svgNode('svg', { viewBox: `0 0 ${width} 470`, role: 'img', 'aria-labelledby': 'chart-title chart-description' });
    svg.append(svgNode('title', { id: 'chart-title' }, `${option.label} versus ${reference.label}: eight-quarter ${names.join(" and ")}`));
    svg.append(svgNode('desc', { id: 'chart-description' }, 'Two separately labelled scales and units. Credibility alone converts from a fraction to a 100-point index; support is already on that scale. Solid line and circles show the chosen path; dashed line shows the reference. Exact observations and differences are in the expandable macro data table below. Scale padding is not an observation.'));
    selectedMetrics.forEach((key, lane) => {
      const top = 42 + lane * 224, bottom = top + 138, left = compact ? 76 : 78, right = width - 22;
      const [, label, unit] = METRICS.find(metric => metric[0] === key);
      svg.append(svgNode('text', { x: 0, y: top - 23, class: 'lane-title' }, label));
      svg.append(svgNode('text', { x: 0, y: top - 3 }, indexMetric(key) ? '/100 index' : unit));
      const values = [...option.path, ...reference.path].map(row => row[key]);
      if (!values.every(finite)) {
        svg.append(svgNode('text', { x: 0, y: top + 65, class: 'unavailable' }, 'Unavailable: incomplete exported series'));
        return;
      }
      const [lo, hi] = extent(values);
      const x = i => left + i * (right - left) / 7;
      const y = v => bottom - (v - lo) / (hi - lo) * (bottom - top);
      for (let i = 0; i <= 2; i++) {
        const value = lo + i * (hi - lo) / 2, yy = y(value);
        svg.append(svgNode('line', { x1: left, x2: right, y1: yy, y2: yy, class: 'grid' }));
        svg.append(svgNode('text', { x: left - 10, y: yy + 5, 'text-anchor': 'end' }, new Intl.NumberFormat('en-US', { maximumFractionDigits: 2, notation: Math.abs(key === 'credibility' ? value * 100 : value) >= 10000 ? 'scientific' : 'standard' }).format(key === 'credibility' ? value * 100 : value)));
      }
      const points = path => path.map((row, i) => `${x(i)},${y(row[key])}`).join(' ');
      // Draw reference last so identical paths still disclose the dashed comparison.
      svg.append(svgNode('polyline', { points: points(option.path), class: 'chosen' }), svgNode('polyline', { points: points(reference.path), class: 'reference' }));
      option.path.forEach((row, i) => {
        svg.append(svgNode('circle', { cx: x(i), cy: y(row[key]), r: 3.5, class: 'point' }));
        if (!compact || [0, 3, 7].includes(i)) svg.append(svgNode('text', { x: x(i), y: bottom + 27, 'text-anchor': 'middle' }, `Q${row.quarter}`));
      });
    });
    $('chart').replaceChildren(svg);
  }
  function makeTable(caption, headers, rows) {
    const table = element('table'); table.append(element('caption', caption));
    const head = element('thead'), hr = element('tr');
    for (const header of headers) hr.append(element('th', header, { scope: 'col' }));
    head.append(hr); table.append(head);
    const body = element('tbody');
    for (const row of rows) {
      const tr = element('tr');
      row.forEach((value, i) => tr.append(element(i === 0 ? 'th' : 'td', value, i === 0 ? { scope: 'row' } : {})));
      body.append(tr);
    }
    table.append(body); return table;
  }
  function renderWorkout(option, reference) {
    const offset = Number($('ledger-quarter').value);
    const chosen = firstCreditSettlement(option, offset), baseline = firstCreditSettlement(reference, offset);
    const fields = [['apr', 'Contractual loan APR (annual %)', 'annual_rate_pct'], ['paidToFed', 'Bank pays Fed', 'assets'], ['paidToBank', 'Fed pays bank', 'assets'], ['unpaidToFed', 'Unpaid interest to Fed', 'assets'], ['unpaidFromFed', 'Unpaid interest from Fed', 'assets']];
    const display = (value, key) => key === 'annual_rate_pct' ? finite(value) ? `${formatValue(value, key)}% APR` : 'Unavailable' : formatValue(value, key);
    $('credit-summary').replaceChildren(makeTable(`Exported settlement, Q${option.path[offset].quarter}`, ['Borrowing cost', 'Chosen', 'Reference'], fields.map(([field, label, key]) => [label, display(chosen[field], key), display(baseline[field], key)])));
    const raw = {};
    for (const [name, entry] of [['chosen', option], ['reference', reference]]) {
      const ledger = entry.ledger && typeof entry.ledger === 'object' ? entry.ledger : {};
      raw[name] = Object.fromEntries(OPTIONAL_LEDGERS.filter(key => Array.isArray(ledger[key])).map(key => [key, ledger[key]]));
    }
    $('ledger-details').hidden = !Object.values(raw).some(entry => Object.keys(entry).length);
    $('ledger-raw').textContent = JSON.stringify(raw, null, 2);
  }
  function renderResults() {
    const lesson = data.lessons[state.index], option = lesson.options.find(o => o.id === state.choices[lesson.id]), reference = lesson.options[0];
    [...$('options').children].forEach((button, i) => button.setAttribute('aria-pressed', String(lesson.options[i] === option)));
    $('results').hidden = !option; $('empty-path').hidden = !!option; $('takeaway-section').hidden = !option;
    $('progress').textContent = `${Object.keys(state.choices).length} of 8 lessons have a chosen policy`;
    $('path-context').textContent = option ? `${option.label} against ${reference.label}. Same lesson, matched quarters; separate vertical scales.` : 'Choose a policy to reveal its exported path. Nothing is calculated by an economic engine here.';
    $('workout-ledger').hidden = !option || !isWorkout(lesson);
    if (!option) { $('chart').replaceChildren(); $('endpoints').replaceChildren(); $('data-table').replaceChildren(); return; }
    drawChart(option, reference);
    const last = option.path[7], base = reference.path[7];
    const summary = selectedMetrics.map(key => {
      const label = METRICS.find(metric => metric[0] === key)[1];
      return [label, formatValue(last[key], key), formatValue(base[key], key), formatValue(difference(last[key], base[key]), key, true)];
    });
    const showFundingPeak = fundingRelevant(lesson, selectedMetrics);
    if (showFundingPeak) {
      const chosenPeak = fundingPeak(option.path), referencePeak = fundingPeak(reference.path);
      summary.push([`Peak uncovered funding, Q${option.path[0].quarter}–Q${last.quarter}`, formatValue(chosenPeak, 'uncovered_funding'), formatValue(referencePeak, 'uncovered_funding'), formatValue(difference(chosenPeak, referencePeak), 'uncovered_funding', true)]);
    }
    $('endpoints').replaceChildren(makeTable(`At Q${last.quarter}${showFundingPeak ? '; funding row shows each path’s eight-quarter peak, which may occur at different quarters' : ''}`, ['Outcome', 'Chosen', 'Reference', 'Difference'], summary));
    if (isWorkout(lesson)) renderWorkout(option, reference);
    $('data-table').replaceChildren();
    for (const [key, label, unit] of METRICS) {
      $('data-table').append(makeTable(`${label} (${unit})`, ['Path', ...option.path.map(row => `Q${row.quarter}`)], [
        [option.label, ...option.path.map(row => formatValue(row[key], key))],
        [`Reference: ${reference.label}`, ...reference.path.map(row => formatValue(row[key], key))],
        ['Chosen − reference', ...option.path.map((row, i) => formatValue(difference(row[key], reference.path[i][key]), key, true))]
      ]));
    }
  }
  async function start() {
    try {
      const response = await fetch('lessons.json', { cache: 'no-store', credentials: 'same-origin' });
      if (!response.ok) throw new Error(`Lesson file unavailable (HTTP ${response.status}).`);
      data = validateDataset(await response.json());
    } catch (error) {
      $('status').classList.add('error');
      announce(`Lesson data unavailable. ${error instanceof SyntaxError ? 'The local JSON file is not valid.' : error.message} No outcomes have been substituted. If opened as a file, local JSON loading may be blocked; use the supplied static hosting context or the native app.`);
      return;
    }
    let raw = null;
    try { raw = localStorage.getItem(STORAGE_KEY); } catch { storageFailure(); }
    state = parseProgress(raw, data);
    for (let index = 0; index < 2; index++) {
      const select = $(`metric-${index}`);
      for (const [key, label, unit] of METRICS) select.append(element('option', `${label} (${indexMetric(key) ? '/100 index' : unit})`, { value: key }));
      select.addEventListener('change', () => {
        if (!METRICS.some(metric => metric[0] === select.value)) return;
        selectedMetrics[index] = select.value;
        metricChoices.set(data.lessons[state.index].id, [...selectedMetrics]);
        renderResults();
        announce('Primary chart and quarter-eight summary updated to the selected metrics.');
      });
    }
    for (const [title, path, description] of ATLAS) {
      const li = element('li'); addLink(li, title, path); li.append(element('span', description)); $('atlas').append(li);
    }
    $('ledger-quarter').addEventListener('change', renderResults);
    $('back').addEventListener('click', () => { if (state.index > 0) navigate(state.index - 1); });
    $('next').addEventListener('click', () => { if (state.index < 7) navigate(state.index + 1); });
    $('reset').disabled = false;
    $('reset').addEventListener('click', () => {
      try { localStorage.removeItem(STORAGE_KEY); } catch { storageFailure(); }
      state = { index: 0, choices: {} }; metricChoices.clear(); renderLesson();
      announce('Walkthrough progress reset. Native careers are unchanged.');
      $('desk').focus();
    });
    window.matchMedia('(max-width:480px)').addEventListener('change', renderResults);
    renderLesson(); $('experience').hidden = false;
    announce('Eight lessons ready. Choose a policy to compare its precomputed path.');
  }
  start();
})();
