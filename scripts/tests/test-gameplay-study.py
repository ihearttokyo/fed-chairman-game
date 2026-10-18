"""Exercise the actual offline study CLI; no game, model or participant is run."""
import hashlib
import contextlib
import io
import importlib.util
import json
from pathlib import Path
import subprocess
import stat
import sys
import tempfile
import uuid
from types import SimpleNamespace
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
# Retained study data must never enter this or another Git checkout.
with tempfile.TemporaryDirectory(prefix='fed-study-outside-') as external:
    outside = Path(external).resolve()
    manifest = write(outside/'manifest.json', a)
    snapshot = outside/'snapshot.txt'; snapshot.write_text('synthetic visible information')
    checkpoint = outside/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
    alias = outside/'alias'; alias.symlink_to(ROOT, target_is_directory=True)
    name = '.study-boundary-' + uuid.uuid4().hex
    for target in (ROOT/name, alias/name):
        result = run('prepare', target, '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint, ok=False)
        assert 'repository' in result.stderr and not target.exists()
        checks += 1
# The actual writer must sync its file AND directory before reporting success.
with tempfile.TemporaryDirectory(prefix='fed-study-sync-') as temporary:
    d = Path(temporary).resolve()
    calls = []
    original_sync = module.os.fsync
    def traced_sync(fd):
        info = module.os.fstat(fd)
        calls.append(('directory' if stat.S_ISDIR(info.st_mode) else 'file', info.st_ino))
        return original_sync(fd)
    with patch.object(module.os, 'fsync', side_effect=traced_sync):
        module.store(d, 'prepared', {'fixture': True}, {})
    assert [kind for kind, _ in calls] == ['file', 'directory'], 'Sync file then its directory entry'
    checks += 1
with tempfile.TemporaryDirectory(prefix='fed-study-parent-sync-') as temporary:
    d = Path(temporary).resolve()
    manifest = write(d/'manifest.json', a)
    snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic current information')
    checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
    calls.clear()
    with patch.object(module.os, 'fsync', side_effect=traced_sync):
        module.prepare(Namespace(manifest=manifest, snapshot=snapshot, checkpoint=checkpoint, study=d/'study'))
    assert [kind for kind, _ in calls] == ['file', 'directory', 'directory']
    assert calls[-1][1] == d.stat().st_ino, 'New study directory entry must also be synced in its parent'
    checks += 2
# Other checkouts need the same guard, including Git's worktree-file marker.
for marker in ('directory', 'worktree_file'):
    with tempfile.TemporaryDirectory(prefix='fed-other-repository-') as temporary:
        d = Path(temporary).resolve()
        checkout = d/'checkout'; checkout.mkdir()
        if marker == 'directory':
            (checkout/'.git').mkdir()
        else:
            (checkout/'.git').write_text('gitdir: /synthetic/retained-worktree-metadata')
        manifest = write(d/'manifest.json', a)
        snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic visible information')
        checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
        result = run('prepare', checkout/'study', '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint, ok=False)
        assert 'repository' in result.stderr and not (checkout/'study').exists()
        checks += 1
# A directory-sync fault must report failure and preserve the already written file.
for fail_at in (1, 2, 3):
    with tempfile.TemporaryDirectory(prefix='fed-study-sync-fault-') as temporary:
        d = Path(temporary).resolve()
        manifest = write(d/'manifest.json', a)
        snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic visible information')
        checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
        calls.clear()
        def failing_directory_sync(fd):
            calls.append(fd)
            if len(calls) == fail_at:
                assert stat.S_ISDIR(module.os.fstat(fd).st_mode) == (fail_at > 1)
                raise OSError('injected directory-sync failure')
            return original_sync(fd)
        argv = ['gameplay-study.py', 'prepare', str(d/'study'), '--manifest', str(manifest),
                '--snapshot', str(snapshot), '--checkpoint', str(checkpoint)]
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(module.sys, 'argv', argv), patch.object(module.os, 'fsync', side_effect=failing_directory_sync), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = module.main()
        assert code == 1 and not output.getvalue() and 'injected directory-sync failure' in errors.getvalue()
        retained = (d/'study/prepared.json').read_bytes()
        assert retained
        run('prepare', d/'study', '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint, ok=False)
        assert (d/'study/prepared.json').read_bytes() == retained
        blocked = run('status', d/'study', ok=False)
        assert 'incomplete' in blocked.stderr.lower(), 'A failed sync must quarantine the retained trial'
        checks += 4
# macOS needs its stronger drive flush after file and directory metadata sync.
for preparing in (False, True):
    with tempfile.TemporaryDirectory(prefix='fed-study-fullsync-') as temporary:
        d = Path(temporary).resolve()
        events = []
        def ordered_sync(fd):
            events.append('directory' if stat.S_ISDIR(module.os.fstat(fd).st_mode) else 'file')
            return original_sync(fd)
        def full_sync(fd, operation):
            assert operation == 51 and stat.S_ISREG(module.os.fstat(fd).st_mode)
            events.append('fullsync')
            return 0
        adapter = SimpleNamespace(F_FULLFSYNC=51, fcntl=full_sync)
        with patch.object(module.sys, 'platform', 'darwin'), patch.dict(module.__dict__, {'fcntl': adapter}), patch.object(module.os, 'fsync', side_effect=ordered_sync):
            if preparing:
                manifest = write(d/'manifest.json', a)
                snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic visible information')
                checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
                module.prepare(Namespace(manifest=manifest, snapshot=snapshot, checkpoint=checkpoint, study=d/'study'))
            else:
                module.store(d, 'prepared', {'fixture': True}, {})
        assert events == ['file', 'directory'] + (['directory'] if preparing else []) + ['fullsync'], 'macOS full flush must follow all metadata syncs'
        checks += 1
with tempfile.TemporaryDirectory(prefix='fed-study-posix-sync-') as temporary:
    d = Path(temporary).resolve()
    def unexpected_fullsync(*_args):
        raise AssertionError('Non-macOS host must not call the macOS-only primitive')
    with patch.object(module.sys, 'platform', 'linux'), patch.dict(module.__dict__, {'fcntl': SimpleNamespace(F_FULLFSYNC=51, fcntl=unexpected_fullsync)}):
        module.store(d, 'prepared', {'fixture': True}, {})
    assert (d/'prepared.json').is_file()
    checks += 1
with tempfile.TemporaryDirectory(prefix='fed-study-fullsync-fault-') as temporary:
    d = Path(temporary).resolve()
    manifest = write(d/'manifest.json', a)
    snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic visible information')
    checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
    def rejected_fullsync(*_args):
        raise OSError('injected full-sync failure')
    argv = ['gameplay-study.py', 'prepare', str(d/'study'), '--manifest', str(manifest),
            '--snapshot', str(snapshot), '--checkpoint', str(checkpoint)]
    output, errors = io.StringIO(), io.StringIO()
    with patch.object(module.sys, 'platform', 'darwin'), patch.object(module.sys, 'argv', argv), patch.dict(module.__dict__, {'fcntl': SimpleNamespace(F_FULLFSYNC=51, fcntl=rejected_fullsync)}), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
        code = module.main()
    assert code == 1 and not output.getvalue() and 'injected full-sync failure' in errors.getvalue()
    retained = (d/'study/prepared.json').read_bytes()
    run('prepare', d/'study', '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint, ok=False)
    assert (d/'study/prepared.json').read_bytes() == retained
    blocked = run('status', d/'study', ok=False)
    assert 'incomplete' in blocked.stderr.lower()
    checks += 3
# Canonically equivalent names cannot fill the second independent-rater slot.
with tempfile.TemporaryDirectory(prefix='fed-study-unicode-raters-') as temporary:
    d = Path(temporary).resolve()
    manifest = write(d/'manifest.json', a)
    snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic current information')
    checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
    study = d/'study'
    run('prepare', study, '--manifest', manifest, '--snapshot', snapshot, '--checkpoint', checkpoint)
    choice = write(d/'choice.json', {'plan': 0, 'current_signal': 'fixture', 'expected_effect': 'fixture', 'reversal_condition': 'fixture'})
    run('lock', study, '--record', choice)
    rating_value = {'rater': 'Jos\u00e9', 'signal': True, 'channel': True, 'reversal': True, 'reason': 'fixture'}
    rating = write(d/'rating.json', rating_value)
    run('rate', study, '--slot', '1', '--record', rating)
    rating_value['rater'] = ' JOSE\u0301 '
    write(rating, rating_value)
    rejected = run('rate', study, '--slot', '2', '--record', rating, ok=False)
    assert 'distinct rater' in rejected.stderr and not (study/'rating2.json').exists()
    _, previous = module.state(study)
    module.store(study, 'rating2', rating_value, previous)
    rejected = run('status', study, ok=False)
    assert 'distinct rater' in rejected.stderr
    checks += 2
# Every stage remains quarantined after a post-write sync failure; a next action must fail.
for failing_stage in module.STAGES:
    with tempfile.TemporaryDirectory(prefix='fed-study-stage-quarantine-') as temporary:
        d = Path(temporary).resolve()
        manifest = write(d/'manifest.json', a)
        snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic current information')
        checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
        study = d/'study'
        module.prepare(Namespace(manifest=manifest, snapshot=snapshot, checkpoint=checkpoint, study=study))
        records = {'choice': {'plan': 0, 'current_signal': 'fixture', 'expected_effect': 'fixture', 'reversal_condition': 'fixture'},
            'rating1': {'rater': 'first', 'signal': True, 'channel': True, 'reversal': True, 'reason': 'fixture'},
            'rating2': {'rater': 'second', 'signal': True, 'channel': True, 'reversal': True, 'reason': 'fixture'},
            'reveal': {'path': str(snapshot), 'sha256': module.digest(snapshot)},
            'feedback': {'agency': 1, 'comprehensibility': 1, 'repetition': 1, 'confusion': 1, 'arithmetic_seconds': 0, 'continue_playing': False}}
        if failing_stage == 'prepared':
            # A marker alone models interruption before the first envelope is created.
            (study/'.incomplete').touch()
        else:
            for stage in module.STAGES[1:]:
                _, previous = module.state(study)
                if stage == failing_stage:
                    with patch.object(module.os, 'fsync', side_effect=OSError('stage-sync failure')):
                        try:
                            module.store(study, stage, records[stage], previous)
                        except OSError:
                            pass
                        else:
                            raise AssertionError('Injected sync failure must propagate')
                    assert (study/(stage+'.json')).is_file()
                    break
                module.store(study, stage, records[stage], previous)
        blocked = run('status', study, ok=False)
        assert 'incomplete' in blocked.stderr.lower()
        blocked = run('reveal', study, '--record', snapshot, ok=False)
        assert 'incomplete' in blocked.stderr.lower() and (study/'.incomplete').exists()
        checks += 2
# Stored names are normalized too, even when no subsequent hash binding exists yet.
assert module.rater_id('Jos\u00e9') == module.rater_id(' JOSE\u0301 ')
checks += 1
# A reader must not accept a concurrently published envelope whose sync failed.
with tempfile.TemporaryDirectory(prefix='fed-study-concurrent-sync-') as temporary:
    d = Path(temporary).resolve()
    manifest = write(d/'manifest.json', a)
    snapshot = d/'snapshot.txt'; snapshot.write_text('synthetic current information')
    checkpoint = d/'checkpoint.bin'; checkpoint.write_bytes(b'synthetic checkpoint')
    study = d/'study'
    module.prepare(Namespace(manifest=manifest, snapshot=snapshot, checkpoint=checkpoint, study=study))
    records['reveal'] = {'path': str(snapshot), 'sha256': module.digest(snapshot)}
    for stage in module.STAGES[1:]:
        _, previous = module.state(study)
        module.store(study, stage, records[stage], previous)
    original_data = module.data
    def publish_failed_marker(path):
        payload = original_data(path)
        if Path(path) == study/'feedback.json':
            (study/'.incomplete').touch(exist_ok=False)
        return payload
    with patch.object(module, 'data', side_effect=publish_failed_marker):
        try:
            module.state(study)
        except ValueError as error:
            assert 'incomplete' in str(error).lower()
        else:
            raise AssertionError('Concurrent failed write must invalidate this read')
    checks += 1
assert module.rater_id('\u03b1\u0345\u0301') == module.rater_id('\u03b1\u0301\u0345'), 'Normalize canonical order before casefold'
checks += 1
print(f'PASS: {checks} study checks (real CLI paths and deterministic inter-read fixtures); synthetic records only')
