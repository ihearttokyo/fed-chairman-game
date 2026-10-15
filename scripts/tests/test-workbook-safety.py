"""Exercise workbook output and process boundaries without authoring a workbook."""
import importlib.util
import ast
import hashlib
import json
import math
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from unittest.mock import patch

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


# Managed package metadata identifies bundled/nested versions without loading Node.
with tempfile.TemporaryDirectory(prefix='fed-workbook-dependencies-') as directory:
    modules = Path(directory) / 'node_modules'
    package_data = {
        '@oai/artifact-tool/package.json': {
            'name': '@oai/artifact-tool', 'version': '2.8.91',
            'dependencies': {'skia-canvas': '^3.0.6', '@oai/walnut': '0.1.258'},
            'bundledDependencies': ['@oai/walnut', 'skia-canvas'],
        },
        '@oai/artifact-tool/node_modules/@oai/walnut/package.json': {
            'name': '@oai/walnut', 'version': '0.1.258',
        },
        '@oai/artifact-tool/node_modules/skia-canvas/package.json': {
            'name': 'skia-canvas', 'version': '3.0.8',
        },
        'debug/package.json': {'name': 'debug', 'version': '4.4.3'},
    }
    for relative, data in package_data.items():
        path = modules / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))
    lock = modules / '.pnpm/lock.yaml'
    lock.parent.mkdir()
    lock.write_text("lockfileVersion: '9.0'\n")
    original = builder.dependency_provenance(modules)
    artifact = modules / '@oai/artifact-tool/package.json'
    assert original['artifact_tool'] == {
        'name': '@oai/artifact-tool', 'version': '2.8.91',
        'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(),
    }
    assert len(original['package_manifests']) == 4
    assert original['lockfiles_sha256'] == {'.pnpm/lock.yaml': hashlib.sha256(lock.read_bytes()).hexdigest()}
    identity_bytes = json.dumps({'package_manifests': original['package_manifests'],
                                 'lockfiles_sha256': original['lockfiles_sha256']},
                                sort_keys=True, separators=(',', ':')).encode()
    assert original['dependency_set_sha256'] == hashlib.sha256(identity_bytes).hexdigest()
    assert builder.dependency_provenance(modules) == original, 'Stable metadata has stable provenance'
    changes = 0
    for relative in package_data:
        path = modules / relative
        raw = path.read_bytes()
        data = json.loads(raw)
        data['version'] += '-changed'
        path.write_text(json.dumps(data))
        assert builder.dependency_provenance(modules)['dependency_set_sha256'] != original['dependency_set_sha256'], relative
        path.write_bytes(raw)
        changes += 1
    raw = artifact.read_bytes()
    artifact.write_bytes(raw + b'\n')
    changed = builder.dependency_provenance(modules)
    assert changed['artifact_tool']['version'] == original['artifact_tool']['version']
    assert changed['artifact_tool']['sha256'] != original['artifact_tool']['sha256']
    assert changed['dependency_set_sha256'] != original['dependency_set_sha256']
    artifact.write_bytes(raw)
    changes += 1
    lock.write_text("lockfileVersion: '9.0'\n# changed installation\n")
    assert builder.dependency_provenance(modules)['dependency_set_sha256'] != original['dependency_set_sha256']
    lock.rename(lock.with_suffix('.absent'))
    without_lock = builder.dependency_provenance(modules)
    assert without_lock['lockfiles_sha256'] == {} and len(without_lock['package_manifests']) == 4
    assert without_lock['dependency_set_sha256'] != original['dependency_set_sha256']
    changes += 2
    added = modules / 'added/package.json'
    added.parent.mkdir()
    added.write_text('{"name":"added","version":"1.0.0"}')
    assert builder.dependency_provenance(modules)['dependency_set_sha256'] != without_lock['dependency_set_sha256']
    changes += 1
    invalid_metadata = [
        (artifact, None), (artifact, b'{'), (artifact, b'[]'),
        (artifact, b'{"version":"2.8.91"}'),
        (artifact, b'{"name":"@oai/artifact-tool"}'),
        (artifact, b'{"name":"@oai/artifact-tool","version":" "}'),
        (artifact, b'{"name":"@oai/artifact-tool","version":2}'),
        (artifact, b'{"name":"other","version":"2.8.91"}'),
        (modules / '@oai/artifact-tool/node_modules/skia-canvas/package.json', b'{'),
        (modules / '@oai/artifact-tool/node_modules/@oai/walnut/package.json', None),
        (added, b'{"name":"added"}'),
    ]
    rejected = 0
    for path, replacement in invalid_metadata:
        raw = path.read_bytes()
        if replacement is None:
            path.rename(path.with_suffix('.absent'))
        else:
            path.write_bytes(replacement)
        try:
            builder.dependency_provenance(modules)
        except ValueError as error:
            assert 'manifest' in str(error), error
            rejected += 1
        else:
            raise AssertionError(f'Accepted invalid managed metadata: {path}')
        output = Path(directory) / 'must-not-be-created'
        arguments = ['build-workbook.py', str(output), '--node', sys.executable,
                     '--godot', sys.executable, '--modules', str(modules)]
        with patch.object(sys, 'argv', arguments), patch.object(
                builder.subprocess, 'check_output',
                side_effect=AssertionError('Metadata refusal must precede tool invocation')):
            try:
                builder.main()
            except ValueError as error:
                assert 'manifest' in str(error), error
            else:
                raise AssertionError('CLI preflight accepted invalid dependency metadata')
        assert not output.exists(), 'Invalid metadata must not reserve output'
        if replacement is None:
            path.with_suffix('.absent').rename(path)
        else:
            path.write_bytes(raw)
    assert rejected == len(invalid_metadata)
print(f'PASS: managed dependency provenance: 4 manifests, {changes} identity changes, {rejected} metadata refusals (Python fixtures)')


# pnpm resolves hidden transitive packages through sibling links in its virtual store.
with tempfile.TemporaryDirectory(prefix='fed-workbook-pnpm-') as directory:
    modules = Path(directory) / 'node_modules'
    store = modules / '.pnpm'
    artifact = store / '@oai+artifact-tool@2.8.91/node_modules/@oai/artifact-tool'
    hidden = store / '@scope+hidden@1.0.0/node_modules/@scope/hidden'
    leaf = hidden / 'node_modules/@nested/leaf'
    for package, name, version in ((artifact, '@oai/artifact-tool', '2.8.91'),
                                   (hidden, '@scope/hidden', '1.0.0'),
                                   (leaf, '@nested/leaf', '1.0.0')):
        package.mkdir(parents=True)
        (package / 'package.json').write_text(json.dumps({'name': name, 'version': version}))
    (modules / '@oai').mkdir()
    (modules / '@oai/artifact-tool').symlink_to(artifact, target_is_directory=True)
    sibling = artifact.parent.parent / '@scope/hidden'
    sibling.parent.mkdir()
    sibling.symlink_to(hidden, target_is_directory=True)
    hoisted = store / 'node_modules/@scope/hidden'
    hoisted.parent.mkdir(parents=True)
    hoisted.symlink_to(hidden, target_is_directory=True)
    cycle = hidden / 'node_modules/@scope/hidden'
    cycle.parent.mkdir()
    cycle.symlink_to(hidden, target_is_directory=True)
    lock = store / 'lock.yaml'
    lock.write_text("lockfileVersion: '9.0'\n")
    original = builder.dependency_provenance(modules)
    manifest = hidden / 'package.json'
    raw = manifest.read_bytes()
    for replacement in (b'{"name":"@scope/hidden","version":"1.0.1"}', raw + b'\n'):
        manifest.write_bytes(replacement)
        changed = builder.dependency_provenance(modules)
        assert changed['dependency_set_sha256'] != original['dependency_set_sha256'], 'pnpm transitive manifest change must alter identity even with unchanged lock'
        assert changed['lockfiles_sha256'] == original['lockfiles_sha256']
        assert changed['artifact_tool'] == original['artifact_tool']
        manifest.write_bytes(raw)
    paths = original['package_manifests']
    assert str(manifest.relative_to(modules)) in paths, 'Include unexposed virtual-store package'
    assert {'name': '@nested/leaf', 'version': '1.0.0', 'sha256': hashlib.sha256((leaf / 'package.json').read_bytes()).hexdigest()} in paths.values(), 'Retain exact nested scoped manifest even when cycle deduplication visits an alias first'
    before = (leaf / 'package.json').read_bytes()
    (leaf / 'package.json').write_bytes(before + b'\n')
    nested_change = builder.dependency_provenance(modules)
    assert nested_change['dependency_set_sha256'] != original['dependency_set_sha256'] and nested_change['lockfiles_sha256'] == original['lockfiles_sha256']
    (leaf / 'package.json').write_bytes(before)
    assert str((hoisted / 'package.json').relative_to(modules)) in paths, 'Include pnpm hoisted dependencies'
    assert list(paths) == sorted(paths) and builder.dependency_provenance(modules) == original, 'Cycles terminate with deterministic metadata'
    main = next(node for node in ast.parse((ROOT / 'scripts/build-workbook.py').read_text()).body
                if isinstance(node, ast.FunctionDef) and node.name == 'main')
    guard = next(node for node in main.body if isinstance(node, ast.If)
                 and 'Managed dependency metadata changed during the build' in ast.unparse(node))
    guard_code = compile(ast.fix_missing_locations(ast.Module(body=[guard], type_ignores=[])), '<actual dependency drift guard>', 'exec')
    guard_values = {'dependency_provenance': builder.dependency_provenance,
                    'args': builder.argparse.Namespace(modules=modules), 'dependencies': original}
    exec(guard_code, guard_values)
    manifest.write_bytes(raw + b'\n')
    try:
        exec(guard_code, guard_values)
    except ValueError as error:
        assert 'metadata changed' in str(error), error
    else:
        raise AssertionError('Production drift guard accepted changed pnpm transitive metadata')
    manifest.write_bytes(raw)
    rejected = 0
    for path, replacement in ((manifest, None), (manifest, b'{'),
                              (leaf / 'package.json', b'{"name":"@nested/leaf"}')):
        before = path.read_bytes()
        if replacement is None:
            path.rename(path.with_suffix('.absent'))
        else:
            path.write_bytes(replacement)
        try:
            builder.dependency_provenance(modules)
        except ValueError as error:
            assert 'manifest' in str(error), error
            rejected += 1
        else:
            raise AssertionError('Accepted missing/malformed virtual-store metadata')
        if replacement is None:
            path.with_suffix('.absent').rename(path)
        else:
            path.write_bytes(before)
    broken = artifact.parent.parent / 'broken'
    broken.symlink_to(store / 'missing-package', target_is_directory=True)
    try:
        builder.dependency_provenance(modules)
    except ValueError as error:
        assert 'Missing managed package manifest' in str(error), error
        rejected += 1
    else:
        raise AssertionError('Accepted dangling pnpm sibling link')
    assert rejected == 4
print('PASS: pnpm virtual-store metadata: 3 unchanged-lock identity changes, nested/scoped/cyclic links, actual drift guard and 4 refusals (Python fixtures)')


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

# Execute the actual identity guard and digest on real matching/mismatching files.
identity_code = r"""
import ast, hashlib, sys
from pathlib import Path
source = ast.parse(Path(sys.argv[1]).read_text())
main = next(node for node in source.body if isinstance(node, ast.FunctionDef) and node.name == 'main')
selected = [node for node in main.body if ast.unparse(node).startswith('digest = lambda') or 'Execution copy differs from source' in ast.unparse(node)]
if len(selected) != 2:
    raise RuntimeError('Production source-copy identity guard missing')
module = ast.fix_missing_locations(ast.Module(body=selected, type_ignores=[]))
exec(compile(module, '<actual workbook identity guard>', 'exec', optimize=sys.flags.optimize),
     {'hashlib': hashlib, 'builder': Path(sys.argv[2]), 'execution_copy': Path(sys.argv[3])})
"""
with tempfile.TemporaryDirectory(prefix='fed-source-copy-identity-') as directory:
    original = Path(directory) / 'source.mjs'
    copy = Path(directory) / 'execution.mjs'
    original.write_text('same source')
    modes = [([], dict(os.environ, PYTHONOPTIMIZE='')),
             (['-O'], dict(os.environ, PYTHONOPTIMIZE='')),
             ([], dict(os.environ, PYTHONOPTIMIZE='1'))]
    failures = []
    for flags, environment in modes:
        for changed in (False, True):
            copy.write_text('different source' if changed else 'same source')
            result = subprocess.run([sys.executable, *flags, '-c', identity_code,
                                     str(ROOT / 'scripts/build-workbook.py'), str(original), str(copy)],
                                    capture_output=True, text=True, env=environment)
            if changed:
                if result.returncode == 0 or 'Execution copy differs from source' not in result.stderr:
                    failures.append('Optimized source-copy mismatch accepted')
            elif result.returncode != 0:
                failures.append('Matching source copy rejected: ' + result.stderr)
    if failures:
        raise AssertionError('\n'.join(failures))
print('PASS: actual source-copy guard accepts matches and rejects drift in normal/-O/inherited modes')

# input54: the actual typed-literal guard keeps blank, numeric and boolean inputs distinct.
input54_tree = ast.parse((ROOT / 'scripts/spreadsheet/check-workbook.py').read_text())
input54_nodes = [node for node in input54_tree.body if isinstance(node, ast.FunctionDef)
                 and node.name in ('require', 'validate_authored_literals', 'saved_string', 'cached_string', 'string_text', 'unsigned_integer')]
assert len(input54_nodes) == 6, 'Locate actual input54 guard and string decoders'
input54_scope = {'NS': {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}, 'math': math, 're': re}
exec(compile(ast.Module(body=input54_nodes, type_ignores=[]), '<actual typed-input guard>', 'exec'), input54_scope)
for expected, kind, raw in [(None, 'n', None), (0, 'n', '0'), (1e-15, 'n', '1e-15'), (True, 'b', '1'), (False, 'b', '0')]:
    xml = '<c xmlns="' + input54_scope['NS']['s'] + '" r="A1" t="' + kind + '">' + ('' if raw is None else '<v>' + raw + '</v>') + '</c>'
    input54_scope['validate_authored_literals']({'A1': ET.fromstring(xml)}, {'A1': expected}, 'Assumptions')
for expected, children, kind in [(None, '<v>0</v>', 'n'), (0, '', 'n'), (True, '<v>1</v>', 'n'),
                                  (1, '<v>1</v>', 'b'), (1, '<v>1</v>', 'str'), (1e-15, '<v>0</v>', 'n'),
                                  (0.4, '<v>0.40000000000004</v>', 'n'),
                                  (1, '<v>NaN</v>', 'n'), (1, '<f>0</f><v>1</v>', 'n')]:
    cell = ET.fromstring('<c xmlns="' + input54_scope['NS']['s'] + '" r="A1" t="' + kind + '">' + children + '</c>')
    try:
        input54_scope['validate_authored_literals']({'A1': cell}, {'A1': expected}, 'Assumptions')
    except AssertionError as error:
        assert 'authored literal mismatch' in str(error)
    else:
        raise AssertionError('input54 accepted a wrong literal type/value/formula')
for address, value in [('C4', 3), ('C5', 48), ('C6', 1)]:
    cell = ET.fromstring('<c xmlns="' + input54_scope['NS']['s'] + '" r="' + address + '"><v>' + repr(value + 5e-13) + '</v></c>')
    try:
        input54_scope['validate_authored_literals']({address: cell}, {address: value}, 'Policy Lab')
    except AssertionError as error:
        assert 'authored literal mismatch' in str(error)
    else:
        raise AssertionError('label60 accepted a fractional discrete selector')
print('PASS: input54 actual typed source input guard (simulated XML)')

# upstream77 uses the actual literal-only string readers, including shared/rich forms.
for kind, children, strings in [
    ('str', '<v>Authored text</v>', []), ('s', '<v>0</v>', ['Authored text']),
    ('inlineStr', '<is><t>Authored text</t></is>', []),
    ('inlineStr', '<is><r><t>Authored </t></r><r><t>text</t></r></is>', []),
]:
    cell = ET.fromstring('<c xmlns="' + input54_scope['NS']['s'] + '" t="' + kind + '">' + children + '</c>')
    input54_scope['validate_authored_literals']({'A1': cell}, {'A1': 'Authored text'}, 'Assumptions', strings)
for kind, children in [('str', '<f>"Authored text"</f><v>Authored text</v>'),
                       ('n', '<v>2</v>'), ('str', '<v>Changed text</v>'), ('s', '<v>1</v>')]:
    cell = ET.fromstring('<c xmlns="' + input54_scope['NS']['s'] + '" t="' + kind + '">' + children + '</c>')
    try:
        input54_scope['validate_authored_literals']({'A1': cell}, {'A1': 'Authored text'}, 'Assumptions', ['Authored text'])
    except AssertionError as error:
        assert 'authored literal mismatch' in str(error)
    else:
        raise AssertionError('upstream77 accepted wrong authored text/type/formula')
print('PASS: upstream77 actual string guard preserves scalar/shared/rich text and refuses formulas/impostors (simulated XML)')

# Exact authored expressions need no token normalization; differing expressions still do.
checker_tree = ast.parse((ROOT / 'scripts/spreadsheet/check-workbook.py').read_text())
authored_nodes = [node for node in checker_tree.body if isinstance(node, ast.FunctionDef)
                  and node.name in ('require', 'validate_authored_formulas')]
assert len(authored_nodes) == 2, 'Locate actual authored-expression validator'
normalizations = []
authored_scope = {'NS': {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'},
                  'formula_inventory': {'state_fields': [], 'formulas': {'E6': '=D6+1'}},
                  'reference': {'initial_state': {'quarter_index': 0}}, 'rows': {},
                  'canonical_formula': lambda text: normalizations.append(text) or text.strip().removeprefix('=')}
exec(compile(ast.Module(body=authored_nodes, type_ignores=[]), '<actual authored-expression guard>', 'exec'), authored_scope)
for actual, expected_calls in [('D6+1', 0), ('0', 2)]:
    cell = ET.fromstring('<c xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><f/></c>')
    cell[0].text = actual
    normalizations.clear()
    rejected = False
    try:
        authored_scope['validate_authored_formulas']({'E6': cell}, {})
    except AssertionError:
        rejected = True
    assert rejected == (actual == '0'), 'Exact matches pass; wrong expressions refuse'
    assert len(normalizations) == expected_calls, 'Only differing expressions need normalization'
print('PASS: actual authored-expression equality fast path and mismatch refusal (simulated XML cell)')

# meta89: validation normalization preserves anchors; ordinary scalar normalization retains its existing contract.
meta89_nodes = [node for node in checker_tree.body if isinstance(node, ast.FunctionDef) and node.name == 'canonical_formula']
meta89_scope = {'re': re}
meta89_tokens = next(node for node in checker_tree.body if isinstance(node, ast.Assign)
                     and any(isinstance(target, ast.Name) and target.id == 'SAFE_FORMULA_TOKENS' for target in node.targets))
exec(compile(ast.Module(body=[meta89_tokens, *meta89_nodes], type_ignores=[]), '<actual meta89 normalization>', 'exec'), meta89_scope)
meta89_canonical = meta89_scope['canonical_formula']
for anchored in ['E$6', '$E6', '$E$6']:
    assert meta89_canonical('E6') == meta89_canonical(anchored), 'Existing scalar equivalence must remain valid'
    assert meta89_canonical('E6', preserve_anchors=True) != meta89_canonical(anchored, preserve_anchors=True)
for preserve in (False, True):
    assert meta89_canonical(' = if ( E6 = "A$1, Mixed Case", \'Policy Lab\'!$C$5, 0)', preserve) == meta89_canonical(
        'IF(E6="A$1, Mixed Case",\'Policy Lab\'!$C$5,0)', preserve)
    assert '"A$1, Mixed Case"' in meta89_canonical('IF(E6="A$1, Mixed Case",1,0)', preserve)
print('PASS: meta89 actual canonical tokenizer preserves validation anchors, quoted literals, whitespace/case and scalar anchor equivalence (simulated)')

# Checkpoint identity includes the raw portfolio inputs consumed by authoring.
input_nodes = [node for node in ast.walk(checker_tree) if isinstance(node, ast.FunctionDef)
               and node.name in ('require', 'flatten_state', 'authored_inputs')]
assert len(input_nodes) == 3, 'Locate actual checkpoint-input signature'
input_scope = {'json': json}
exec(compile(ast.Module(body=input_nodes, type_ignores=[]), '<actual checkpoint-input signature>', 'exec'), input_scope)
portfolio_fixture = '{"example":1}'
input_fixture = {'parameters': [], 'scenario': {'initial': {}},
                 'initial_state': {'quarter_index': 120, 'price_history': [1] * 5,
                                   'treasury_cohorts_pct_initial_gdp': [0] * 120,
                                   'sterilized_treasury_cohorts_pct_initial_gdp': [0] * 120,
                                   'bill_cohorts_pct_initial_gdp': [0] * 4},
                 'portfolio_reference_json': portfolio_fixture,
                 'portfolio_reference_sha256': hashlib.sha256(portfolio_fixture.encode()).hexdigest()}
original_signature = input_scope['authored_inputs'](input_fixture)
for changed_key in ('portfolio_reference_json', 'portfolio_reference_sha256'):
    changed_fixture = {**input_fixture, changed_key: 'changed portfolio input'}
    assert input_scope['authored_inputs'](changed_fixture) != original_signature, 'Checkpoint signature must bind ' + changed_key
print('PASS: actual checkpoint-input signature binds portfolio JSON/hash (simulated typed reference)')

if sys.argv[1:] == ['--python-only']:
    print('NOT RUN: real engine integration (--python-only)')
    raise SystemExit(0)

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
