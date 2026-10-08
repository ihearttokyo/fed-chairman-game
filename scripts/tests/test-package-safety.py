"""Preserve existing outputs and reject zero-exit Godot runtime errors."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
assert not any((root / path).exists() for path in (
    'native/FedChairmanGame/Package.swift', '.github/workflows/verify.yml',
    'package.json')), 'Godot must be the sole maintained frontend and build path'
with tempfile.TemporaryDirectory(prefix='fed-godot-package-guard-') as directory:
    sentinel = Path(directory) / 'preserved'
    sentinel.write_text('existing output')
    result = subprocess.run(['bash', str(root / 'scripts/package-game.sh'), directory,
                             'unused identity', 'unused team'], capture_output=True, text=True)
    assert result.returncode == 1 and 'Refusing to replace existing output' in result.stderr, result.stderr
    assert sentinel.read_text() == 'existing output'
    assert list(Path(directory).iterdir()) == [sentinel]
print('PASS: Godot packager refuses existing output before export or signing')

# Exercise the real shell boundaries with synthetic engine output, never a real
# export or signing operation. Downstream tripwires stop accidental continuation.
failures = []
workflow = (root / '.github/workflows/godot.yml').read_text()
ci_step = workflow.split('      - name: Import and test playable Godot game\n', 1)[1].split('\n      - ', 1)[0]
ci_commands = [line.strip() for line in ci_step.splitlines() if 'game-check.log' in line]
assert len(ci_commands) == 3, 'CI verification must include engine, error scan and completion scan'
ci_shell = ['bash', '-e']
if '        shell: bash' in ci_step.splitlines():
    ci_shell = ['bash', '--noprofile', '--norc', '-e', '-o', 'pipefail']
with tempfile.TemporaryDirectory(prefix='fed-runtime-error-guards-') as directory:
    temporary = Path(directory)
    tools = temporary / 'bin'
    tools.mkdir()
    engine = tools / 'godot'
    engine.write_text('#!/usr/bin/env bash\ncat "$FED_TEST_LOG"\nexit "$FED_TEST_EXIT"\n')
    engine.chmod(0o755)
    for command in ('lipo', 'codesign'):
        tripwire = tools / command
        tripwire.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$0" >> "$FED_TEST_DOWNSTREAM"\nexit 73\n')
        tripwire.chmod(0o755)
    log = temporary / 'engine-output.log'
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                       RUNNER_TEMP=directory, FED_TEST_LOG=str(log))
    for index, (marker, exit_code) in enumerate((('', 0), ('SCRIPT ERROR:', 0), ('ERROR:', 0), ('FAIL:', 0), ('', 42))):
        trace = temporary / f'downstream-{index}'
        environment['FED_TEST_DOWNSTREAM'] = str(trace)
        environment['FED_TEST_EXIT'] = str(exit_code)
        rejected = bool(marker or exit_code)
        log.write_text((marker + ' synthetic runtime failure\n' if marker else '')
                       + 'PASS: 164 release-safe checks; synthetic output only\n'
                       + 'PASS: comparison count, exact parity and paired timing fixture; synthetic output only\n')
        for script in ('scripts/test-model.sh', 'scripts/test-game.sh'):
            result = subprocess.run(['bash', str(root / script)], env=environment,
                                    capture_output=True, text=True)
            if (result.returncode != 0) != rejected:
                failures.append(f'{script}: wrong result for {marker or "clean output"}, exit {exit_code}')
        result = subprocess.run(ci_shell + ['-c', '\n'.join(ci_commands)], env=environment, cwd=root,
                                capture_output=True, text=True)
        if (result.returncode != 0) != rejected:
            failures.append(f'CI verification: wrong result for {marker or "clean output"}, exit {exit_code}')
        if rejected:
            result = subprocess.run(['bash', str(root / 'scripts/package-game.sh'),
                                     str(temporary / f'export-{index}'), 'unused identity', 'unused team'],
                                    env=environment, capture_output=True, text=True)
            if result.returncode == 0 or trace.exists():
                failures.append(f'packager continued past {marker} before thinning/signing')
    # A generic PASS cannot certify completion of the additional comparison fixture.
    log.write_text('PASS: 164 release-safe checks; synthetic output only\n')
    environment['FED_TEST_EXIT'] = '0'
    incomplete = subprocess.run(['bash', str(root / 'scripts/test-game.sh')],
                                env=environment, capture_output=True, text=True)
    assert incomplete.returncode != 0, 'comparison wrapper must require its own completion marker'
assert not failures, '\n'.join(failures)
print('PASS: runtime log gates reject errors before continuation (synthetic CLI evidence)')

# Simulate engine log writes without launching an engine or accessing real userdata.
import plistlib
import runpy
from unittest.mock import patch
with tempfile.TemporaryDirectory(prefix='fed-release-userdata-guard-') as directory:
    temporary = Path(directory)
    home = temporary / 'player-home'
    protected = home / 'Library/Application Support/FedChairmanPolicyLab/logs/godot.log'
    protected.parent.mkdir(parents=True)
    protected.write_text('player crash evidence')
    app = temporary / 'Candidate.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'candidate', 'CFBundleIdentifier': 'local.fed-chairman-game.policy-lab'}))
    binary = app / 'Contents/MacOS/candidate'
    binary.write_bytes(b'\xcf\xfa\xed\xfe')
    engine_homes = []
    def fake_release_tool(command, **kwargs):
        if '--headless' not in command:
            assert Path((kwargs.get('env') or os.environ)['HOME']) == home, 'signing tools retain normal HOME'
        text = ''
        if command[0] == 'lipo':
            text = 'arm64\n'
        elif command[0] == 'codesign' and '-d' in command:
            text = 'TeamIdentifier=TESTTEAM\nAuthority=Developer ID Application: Fixture\n(runtime)\nTimestamp=fixture\n'
        elif '--headless' in command:
            assert Path(command[0]).resolve() == binary.resolve()
            engine_home = Path(kwargs.get('env', os.environ)['HOME'])
            engine_homes.append(engine_home)
            log = engine_home / 'Library/Application Support/FedChairmanPolicyLab/logs/godot.log'
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text('new verification log')
            text = 'PASS: 164 release-safe checks; synthetic engine only\n'
        return subprocess.CompletedProcess(command, 0, text, '')
    with patch.dict(os.environ, HOME=str(home)), patch('sys.argv', ['verify-game-release.py', str(app), 'TESTTEAM']), patch('subprocess.run', side_effect=fake_release_tool):
        runpy.run_path(str(root / 'scripts/tests/verify-game-release.py'), run_name='__main__')
        assert os.environ['HOME'] == str(home), 'release check must preserve parent HOME'
    assert engine_homes and all(path != home for path in engine_homes), 'release check must isolate engine HOME'
    assert protected.read_text() == 'player crash evidence', 'release check must preserve player logs'
print('PASS: release self-check preserves player userdata (simulated engine writes)')
