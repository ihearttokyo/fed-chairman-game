"""Exercise workbook output and process boundaries without authoring a workbook."""
import importlib.util
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('build_workbook', ROOT / 'scripts/build-workbook.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
assert list(builder.CASES) == [case['id'] for case in json.loads((ROOT / 'game/model/scenarios.json').read_text())], 'Workbook must cover every shipped scenario in its stable order'


def rejected_output(path, message):
    try:
        builder.new_output(str(path))
    except ValueError as error:
        assert message in str(error), error
    else:
        raise AssertionError(f'Accepted unsafe output: {path}')


with tempfile.TemporaryDirectory(prefix='fed-workbook-safety-') as directory:
    temporary = Path(directory)
    existing = temporary / 'existing'
    existing.mkdir()
    sentinel = existing / 'preserved'
    sentinel.write_text('existing user output')
    rejected_output('relative', 'absolute')
    rejected_output(existing, 'Refusing to replace')
    rejected_output(ROOT / 'unexpected-workbook-output', 'Git checkouts')
    other_checkout = temporary / 'other-checkout'
    other_checkout.mkdir()
    (other_checkout / '.git').write_text('gitdir: external')
    rejected_output(other_checkout / 'output', 'Git checkouts')
    alias = temporary / 'alias'
    alias.symlink_to(ROOT, target_is_directory=True)
    rejected_output(alias / 'output', 'Git checkouts')
    dangling = temporary / 'dangling'
    dangling.symlink_to(temporary / 'missing')
    rejected_output(dangling, 'Refusing to replace')
    assert builder.new_output(str(temporary / 'new')) == (temporary / 'new').resolve()
    result = subprocess.run([sys.executable, str(ROOT / 'scripts/build-workbook.py'),
                             str(existing), '--node', '/missing/node', '--modules',
                             '/missing/modules'], capture_output=True, text=True)
    assert result.returncode == 1 and 'Refusing to replace' in result.stderr, result.stderr
    assert sentinel.read_text() == 'existing user output' and list(existing.iterdir()) == [sentinel]
    engine = temporary / 'engine'
    engine.write_text('#!/usr/bin/env python3\nimport os, sys\nfrom pathlib import Path\n'
                      'assert "--log-file" in sys.argv, "native file logger must be redirected"\n'
                      'path = Path(sys.argv[sys.argv.index("--log-file") + 1])\n'
                      'assert path.is_absolute() and path.parent == Path(__file__).parent\n'
                      'path.write_text("synthetic engine log")\n'
                      'print(os.environ["FED_TEST_LOG"])\nraise SystemExit(int(os.environ["FED_TEST_EXIT"]))\n')
    engine.chmod(0o755)
    for index, (text, status, rejected) in enumerate((
        ('EXPORTED good', 0, False), ('ERROR: failure\nEXPORTED good', 0, True),
        ('SCRIPT ERROR: failure\nEXPORTED good', 0, True),
        ('FAIL: failure\nEXPORTED good', 0, True), ('EXPORTED good', 42, True),
        ('no completion marker', 0, True),
    )):
        os.environ.update(FED_TEST_LOG=text, FED_TEST_EXIT=str(status))
        failed = False
        try:
            builder.run_tool([str(engine), '--headless'], temporary / f'tool-{index}.log', 'EXPORTED good')
        except ValueError:
            failed = True
        assert failed == rejected, (text, status)
print('PASS: existing/internal/symlink workbook outputs and runtime-error gates (synthetic CLI evidence)')

# Real engine path: fixed variants must have complete, finite quarterly states.
godot = shutil.which('godot')
assert godot, 'Godot is required for the reference exporter integration check'
engine_logs = Path(tempfile.mkdtemp(prefix='fed-workbook-engine-logs-'))
godot = [godot, '--log-file', str(engine_logs / 'godot.log')]
with tempfile.TemporaryDirectory(prefix='fed-workbook-reference-') as directory:
    output = Path(directory) / 'variants.json'
    result = subprocess.run([*godot, '--headless', '--path', str(ROOT / 'game'),
                             '--script', 'res://tests/export_policy_variants.gd',
                             '--', '--output', str(output)], capture_output=True, text=True)
    assert result.returncode == 0 and 'EXPORTED four' in result.stdout and not any(
        marker in result.stdout + result.stderr for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')), result.stdout + result.stderr
    variants = json.loads(output.read_text())
    assert [v['name'] for v in variants] == ['rate_zero', 'asset_purchase', 'liquidity', 'guidance']
    for variant in variants:
        assert len(variant['states']) == 49
        assert [state['quarter_index'] for state in variant['states']] == list(range(49))
        for state in variant['states']:
            for value in state.values():
                assert all(math.isfinite(number) for number in (value if isinstance(value, list) else [value]))
        state = variant['states'][variant['quarter'] + 1]
        assert state[variant['control'] if variant['control'] != 'policy_rate_request_pct'
                     else 'last_policy_rate_request_pct'] == variant['value']
    before = output.read_bytes()
    result = subprocess.run([*godot, '--headless', '--path', str(ROOT / 'game'),
                             '--script', 'res://tests/export_policy_variants.gd',
                             '--', '--output', str(output)], capture_output=True, text=True)
    assert result.returncode == 1 and output.read_bytes() == before
print('PASS: real Godot four policy edits, complete traces and replacement refusal')

# The physical boundary mode shares the same exporter and replacement guard.
with tempfile.TemporaryDirectory(prefix='fed-price-boundaries-') as directory:
    output = Path(directory) / 'price-boundaries.json'
    command = [*godot, '--headless', '--path', str(ROOT / 'game'),
               '--script', 'res://tests/export_policy_variants.gd', '--',
               '--output', str(output), '--price-boundaries']
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0 and 'EXPORTED three' in result.stdout and not any(
        marker in result.stdout + result.stderr for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')), result.stdout + result.stderr
    boundaries = json.loads(output.read_text())
    assert len(boundaries) == 3
    assert [v['shocks'][0]['supply_innovation_pct'] for v in boundaries] == [-5, 0, 5]
    for fixture in boundaries:
        assert [s['quarter_index'] for s in fixture['states']] == [0, 1]
        for state in fixture['states']:
            assert state['price_index'] > 0
            assert all(state[k] > -100 for k in ('annualized_quarterly_inflation_pct',
                                                'expected_short_inflation_pct', 'expected_long_inflation_pct'))
    before = output.read_bytes()
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 1 and output.read_bytes() == before
print('PASS: real Godot three physical price boundaries and replacement refusal')

# Signed-rate fixtures expose actual policies and all state fields for the formula chain.
with tempfile.TemporaryDirectory(prefix='fed-rate-boundaries-') as directory:
    output = Path(directory) / 'rate-boundaries.json'
    command = [*godot, '--headless', '--path', str(ROOT / 'game'),
               '--script', 'res://tests/export_policy_variants.gd', '--',
               '--output', str(output), '--rate-boundaries']
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0 and 'EXPORTED seven signed-rate boundary traces' in result.stdout and not any(
        marker in result.stdout + result.stderr for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')), result.stdout + result.stderr
    fixtures = json.loads(output.read_text())
    assert [v['name'] for v in fixtures] == ['signed_crossing', 'deep_constraint', 'zero_loading',
                                           'untrusted_guidance', 'conditional_positive',
                                           'conditional_negative', 'unrestricted_positive']
    for fixture in fixtures:
        assert len(fixture['states']) == len(fixture['policies']) + 1
        for q, (policy, state) in enumerate(zip(fixture['policies'], fixture['states'][1:]), 1):
            assert state['quarter_index'] == q
            assert state['policy_rate_pct'] == policy['policy_rate_request_pct']
            assert 0 <= state['stance_adequacy_score'] <= 1
            for value in state.values():
                assert all(math.isfinite(number) for number in (value if isinstance(value, list) else [value]))
    assert fixtures[0]['states'][0]['policy_rate_pct'] < 0
    assert fixtures[1]['states'][1]['stance_best_feasible_distance_pct'] > 0
    assert fixtures[2]['states'][1]['stance_distance_pct'] == fixtures[2]['states'][1]['stance_best_feasible_distance_pct']
    assert all(f['states'][2]['guidance_followthrough_score'] == 1 for f in fixtures[4:6])
    before = output.read_bytes()
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 1 and output.read_bytes() == before
print('PASS: real Godot seven signed-rate boundaries, conditional delivery and replacement refusal')

# Reference exports keep their wider seed and horizon contract, unlike careers.
with tempfile.TemporaryDirectory(prefix='fed-campaign-reference-') as directory:
    paths = []
    episodes = []
    for quarters in (48, 1000):
        output = Path(directory) / f'campaign-{quarters}.json'
        command = [*godot, '--headless', '--path', str(ROOT / 'game'),
                   '--script', 'res://tests/export_reference.gd', '--',
                   '--output', str(output), '--scenario', 'mixed_crises',
                   '--quarters', str(quarters), '--seed', '9223372036854775807',
                   '--policy', 'feedback']
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        assert result.returncode == 0 and 'EXPORTED ' in result.stdout and not any(
            marker in result.stdout + result.stderr for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')), result.stdout + result.stderr
        document = json.loads(output.read_text())
        assert document['seed'] == 9223372036854775807 and len(document['quarters']) == quarters
        assert [row['quarter_index'] for row in document['quarters']] == list(range(1, quarters + 1))
        paths.append(document['shock_path'])
        episodes.append(document['episodes'])
    assert paths[0] == paths[1][:48], 'Campaign exporter must retain exact horizon prefixes'
    assert episodes[0] == [event for event in episodes[1] if event['quarter_index'] < 48], 'Named context retains the same horizon prefix'
    accepted = {record['id'] for record in json.loads((ROOT / 'game/model/exogenous_shocks.json').read_text()) if record['accepted']}
    assert all(event['id'] in accepted for event in episodes[1]), 'Only the accepted top50 enter exports'
    assert any(event['quarter_index'] >= 900 for event in episodes[1]), 'Long reference keeps late curated episodes, not only funding events'
    assert any(shock.get('funding_need_pct_initial_gdp', 0) > 0.1 for shock in paths[1]), 'Long reference retains funding variety as well'
print('PASS: real campaign reference, int64 seed, 1000-quarter horizon and exact prefix')

# Balance fixtures share the same source-bound native exports and file safeguards.
portfolio_bytes = (ROOT / 'game/model/portfolio_reference.json').read_bytes()
portfolio_hash = hashlib.sha256(portfolio_bytes).hexdigest()
portfolio = json.loads(portfolio_bytes)
with tempfile.TemporaryDirectory(prefix='fed-balance-boundaries-') as directory:
    output = Path(directory) / 'balance-boundaries.json'
    command = [*godot, '--headless', '--path', str(ROOT / 'game'),
               '--script', 'res://tests/export_policy_variants.gd', '--',
               '--output', str(output), '--balance-boundaries']
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 0 and 'EXPORTED fifteen' in result.stdout and not any(
        marker in result.stdout + result.stderr for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')), result.stdout + result.stderr
    fixtures = json.loads(output.read_text())
    assert len(fixtures) == 15 and len({f['name'] for f in fixtures}) == 15
    for fixture in fixtures:
        assert json.loads(fixture['portfolio_reference_json']) == portfolio and fixture['portfolio_reference_json'].encode() == portfolio_bytes and fixture['portfolio_reference_sha256'] == portfolio_hash
        assert len(fixture['states']) == len(fixture['policies']) + 1
        for state in fixture['states']:
            for field, count in [('treasury_cohorts_pct_initial_gdp', 120),
                                 ('sterilized_treasury_cohorts_pct_initial_gdp', 120),
                                 ('bill_cohorts_pct_initial_gdp', 4), ('price_history', 5)]:
                assert len(state[field]) == count and all(math.isfinite(v) for v in state[field])
            assert all(tag <= holding for tag, holding in zip(state['sterilized_treasury_cohorts_pct_initial_gdp'], state['treasury_cohorts_pct_initial_gdp']))
            assert all(math.isfinite(v) for value in state.values() for v in (value if isinstance(value, list) else [value]))
    by_name = {f['name']: f for f in fixtures}
    omitted = by_name['omitted_liquidity_eligibility']
    assert 'liquidity_eligibility_pct' not in omitted['shocks'][0]
    assert omitted['states'][1]['liquidity_applied_pct_initial_gdp'] == 0
    assert omitted['states'][1]['uncovered_funding_pct_initial_gdp'] == 3
    assert by_name['natural_runoff']['states'][1]['principal_runoff_pct_initial_gdp'] > 0
    assert by_name['negative_cap_on']['states'][1] == by_name['negative_cap_off']['states'][1]
    assert by_name['uncapped_purchase']['states'][1]['asset_flow_applied_pct_initial_gdp'] == 150
    loans = by_name['uncapped_loan_refinancing']['states']
    assert loans[1]['liquidity_applied_pct_initial_gdp'] == 90
    assert loans[2]['liquidity_repayment_pct_initial_gdp'] == 90 and loans[2]['liquidity_refinancing_applied_pct_initial_gdp'] == 90 and loans[2]['liquidity_new_need_applied_pct_initial_gdp'] == 5
    assert len(by_name['tagged_reinvestment_26']['states']) == 27
    assert any(s['sterilized_principal_runoff_pct_initial_gdp'] > 0 for s in by_name['tagged_runoff_release']['states']), 'Tagged runoff fixture must actually mature tagged principal'
    assert by_name['initial_gap_gdp']['states'][0]['initial_actual_output_index'] == 95
    before = output.read_bytes()
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode == 1 and output.read_bytes() == before
print('PASS: real Godot15 source-bound balance traces, zero-access default, maturity/refinancing/cohorts and replacement refusal')

# Exact raw JSON avoids formatting loss in an otherwise valid native numeric snapshot.
assert all(f['portfolio_reference_json'].encode() == portfolio_bytes for f in fixtures)
print('PASS: exact source JSON bytes and hashes retained in every native balance trace')
