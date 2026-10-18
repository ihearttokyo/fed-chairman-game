"""Exercise the actual offline study CLI; no game, model or participant is run."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch
from argparse import Namespace

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/gameplay-study.py'
checks = 0


def run(*args, ok=True):
    global checks
    result = subprocess.run([sys.executable, '-B', str(SCRIPT), *map(str, args)],
                            text=True, capture_output=True, timeout=10)
    assert (result.returncode == 0) == ok, result.stdout + result.stderr
    checks += 1
    return result


def write(path, value):
    path.write_text(json.dumps(value))
    return path


with tempfile.TemporaryDirectory(prefix='fed-study-') as temporary:
    d = Path(temporary).resolve()
    snapshot = d / 'visible.txt'
    snapshot.write_text('Q4; player-visible current information only (synthetic fixture).')
    checkpoint = d / 'checkpoint.bin'
    checkpoint.write_bytes(b'synthetic native checkpoint; not economic evidence')
    manifest = write(d / 'manifest.json', {
        'study_id': 'fixture', 'scope': 'known_development', 'seed': 1, 'q': 4,
        'source_ids': {'main.gd': hashlib.sha256(b'synthetic source').hexdigest()},
        'runtime_sha256': hashlib.sha256(b'synthetic runtime').hexdigest(),
    })
    study = d / 'study'
    run('prepare', study, '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint)
    assert (study / 'prepared.json').is_file(), 'Preparation must persist immutable input bindings'
    checks += 1
    original = (study / 'prepared.json').read_bytes()
    run('prepare', study, '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint, ok=False)
    assert (study / 'prepared.json').read_bytes() == original
    result = write(d / 'result.json', {'fixture': 'not a genuine economic outcome'})
    run('reveal', study, '--record', result, ok=False)
    choice = write(d / 'choice.json', {'plan': 3, 'current_signal': 'Inherited rate differs from the benchmark.',
                                       'expected_effect': 'Rate continuity should change the lagged demand path.',
                                       'reversal_condition': 'A persistent inflation surprise.'})
    rating = write(d / 'rating.json', {'rater': 'rater-a', 'signal': True, 'channel': True, 'reversal': True,
                                       'reason': 'Synthetic rubric fixture, not a real human rating.'})
    run('rate', study, '--slot', '1', '--record', rating, ok=False)
    run('lock', study, '--record', choice)
    run('lock', study, '--record', choice, ok=False)
    run('reveal', study, '--record', result, ok=False)
    run('rate', study, '--slot', '1', '--record', rating)
    run('rate', study, '--slot', '2', '--record', rating, ok=False)
    data = json.loads(rating.read_text()); data['rater'] = 'rater-b'; data['channel'] = False
    write(rating, data)
    run('rate', study, '--slot', '2', '--record', rating)
    snapshot.write_text('changed after choice')
    run('reveal', study, '--record', result, ok=False)
    snapshot.write_text('Q4; player-visible current information only (synthetic fixture).')
    run('reveal', study, '--record', result)
    run('rate', study, '--slot', '1', '--record', rating, ok=False)
    run('reveal', study, '--record', result, ok=False)
    status = json.loads(run('status', study).stdout)
    assert status['ratings_agree'] is False and status['progression'] == 'not_assessed'
    assert status['heldout_qualification'] == 'not_verified' and status['human_blinding'] == 'not_verified'
    checks += 2
    feedback = write(d / 'feedback.json', {'agency': 5, 'comprehensibility': 6, 'repetition': 4,
        'confusion': 2, 'arithmetic_seconds': 10**400, 'continue_playing': True})
    run('feedback', study, '--record', feedback)
    run('feedback', study, '--record', feedback, ok=False)
    # Mutating the original input record cannot revise its already frozen copy.
    choice.write_text('{}')
    assert json.loads((study / 'choice.json').read_text())['record']['plan'] == 3
    checks += 1
    # Mutating an earlier stored record breaks the next stage's binding.
    stored = study / 'choice.json'
    stored.chmod(0o600)  # Deliberate corruption of this disposable fixture only.
    data = json.loads(stored.read_text()); data['record']['plan'] = 1; write(stored, data)
    run('status', study, ok=False)
    # Reject unsupported qualification claims and JSON type traps before creating output.
    original_manifest = json.loads(manifest.read_text())
    for key, value in [('scope', 'heldout'), ('q', True), ('q', 217), ('seed', False), ('source_ids', {}), ('runtime_sha256', 'invalid')]:
        data = dict(original_manifest); data[key] = value; write(manifest, data)
        target = d / ('invalid-' + key)
        run('prepare', target, '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint, ok=False)
        assert not target.exists()
        checks += 1
# Deterministic inter-read replacement: validation and hashing must share bytes.
spec = importlib.util.spec_from_file_location('gameplay_study', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='fed-study-byte-binding-') as temporary:
    d = Path(temporary).resolve()
    a = {'study_id': 'byte-fixture', 'scope': 'known_development', 'seed': 1, 'q': 4,
         'source_ids': {'main.gd': 'a' * 64}, 'runtime_sha256': 'b' * 64}
    b = dict(a, q=12)
    first, changed = json.dumps(a).encode(), json.dumps(b).encode()
    reads = []
    def swapping_manifest(path):
        if Path(path).name == 'manifest':
            reads.append(path)
            return first if len(reads) == 1 else changed
        return b'fixture'
    with patch.object(module, 'data', side_effect=swapping_manifest):
        module.prepare(Namespace(manifest=d/'manifest', snapshot=d/'snapshot', checkpoint=d/'checkpoint', study=d/'study'))
    prepared = json.loads((d/'study/prepared.json').read_text())['record']
    assert prepared['manifest']['q'] == 4
    assert prepared['inputs']['manifest']['sha256'] == hashlib.sha256(first).hexdigest(), 'Validated manifest must bind those same bytes'
    checks += 2
    chain = d / 'chain'
    chain.mkdir()
    module.store(chain, 'prepared', prepared, {})
    prior = {'prepared.json': module.digest(chain/'prepared.json')}
    selected = {'plan': 3, 'current_signal': 'fixture', 'expected_effect': 'fixture', 'reversal_condition': 'fixture'}
    module.store(chain, 'choice', selected, prior)
    choice_path = chain / 'choice.json'
    original_choice = choice_path.read_bytes()
    changed_choice = json.loads(original_choice)
    changed_choice['record']['plan'] = 7
    changed_choice = json.dumps(changed_choice).encode()
    prior['choice.json'] = hashlib.sha256(changed_choice).hexdigest()
    module.store(chain, 'rating1', {'rater': 'fixture-a', 'signal': True, 'channel': True,
                                  'reversal': True, 'reason': 'fixture'}, prior)
    real_data = module.data
    reads.clear()
    def swapping_choice(path):
        if Path(path) == choice_path:
            reads.append(path)
            return original_choice if len(reads) == 1 else changed_choice
        if Path(path) == d/'manifest':
            return first
        if Path(path) in (d/'snapshot', d/'checkpoint'):
            return b'fixture'
        return real_data(path)
    with patch.object(module, 'data', side_effect=swapping_choice):
        try:
            module.state(chain)
        except ValueError as error:
            assert 'Changed record binding: rating1' in str(error), error
        else:
            raise AssertionError('Rating must not authenticate a different parsed choice')
    checks += 1
print(f'PASS: {checks} study checks (real CLI paths and deterministic inter-read fixtures); synthetic records only')
