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
                       + 'PASS: 141 release-safe checks; synthetic output only\n')
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
assert not failures, '\n'.join(failures)
print('PASS: runtime log gates reject errors before continuation (synthetic CLI evidence)')
