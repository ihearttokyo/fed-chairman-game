"""Exercise workbook output and process boundaries without authoring a workbook."""
import importlib.util
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
    engine.write_text('#!/usr/bin/env python3\nimport os\nprint(os.environ["FED_TEST_LOG"])\nraise SystemExit(int(os.environ["FED_TEST_EXIT"]))\n')
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
            builder.run_tool([str(engine)], temporary / f'tool-{index}.log', 'EXPORTED good')
        except ValueError:
            failed = True
        assert failed == rejected, (text, status)
print('PASS: existing/internal/symlink workbook outputs and runtime-error gates (synthetic CLI evidence)')

# Real engine path: fixed variants must have complete, finite quarterly states.
godot = shutil.which('godot')
assert godot, 'Godot is required for the reference exporter integration check'
with tempfile.TemporaryDirectory(prefix='fed-workbook-reference-') as directory:
    output = Path(directory) / 'variants.json'
    result = subprocess.run([godot, '--headless', '--path', str(ROOT / 'game'),
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
    result = subprocess.run([godot, '--headless', '--path', str(ROOT / 'game'),
                             '--script', 'res://tests/export_policy_variants.gd',
                             '--', '--output', str(output)], capture_output=True, text=True)
    assert result.returncode == 1 and output.read_bytes() == before
print('PASS: real Godot four policy edits, complete traces and replacement refusal')

# The physical boundary mode shares the same exporter and replacement guard.
with tempfile.TemporaryDirectory(prefix='fed-price-boundaries-') as directory:
    output = Path(directory) / 'price-boundaries.json'
    command = [godot, '--headless', '--path', str(ROOT / 'game'),
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
