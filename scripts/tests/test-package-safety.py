"""Preserve existing outputs and reject zero-exit Godot runtime errors."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
baseline_marker = 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city'
if f'print("{baseline_marker}")' not in (root / 'game/play/build_check.gd').read_text():
    raise ValueError('Release fixture marker differs from the actual build-check producer')
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
guidance_marker = 'PASS: bundled guidance continuation and comparison'
mandate_marker = 'PASS: bundled mandate assessment and realized feedback'
music_marker = 'PASS: persisted music off survives process relaunch'
incomplete_completions = (
    ('missing mandate', 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\n' + guidance_marker + '\n'),
    ('suffixed mandate', 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\n' + guidance_marker + '\n' + mandate_marker + '; incomplete\n'),
    ('baseline only', 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\n'),
    ('guidance only', guidance_marker + '\n'),
    ('suffixed guidance', 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\n' + guidance_marker + '; incomplete\n'),
)
workflow = (root / '.github/workflows/godot.yml').read_text()
ci_step = workflow.split('      - name: Import and test playable Godot game\n', 1)[1].split('\n      - ', 1)[0]
ci_commands = [line.strip() for line in ci_step.splitlines() if 'game-check.log' in line]
assert len(ci_commands) == 5, 'CI verification must include engine, error scan and all three completion scans'
ci_import = [line.strip() for line in ci_step.splitlines() if '--import' in line]
assert len(ci_import) == 1, 'CI import must have its native logging boundary covered'
ci_shell = ['bash', '-e']
if '        shell: bash' in ci_step.splitlines():
    ci_shell = ['bash', '--noprofile', '--norc', '-e', '-o', 'pipefail']
with tempfile.TemporaryDirectory(prefix='fed-runtime-error-guards-') as directory:
    temporary = Path(directory)
    tools = temporary / 'bin'
    tools.mkdir()
    engine = tools / 'godot'
    engine.write_text('#!/usr/bin/env bash\n'
                      'if [[ -n "${FED_GAME_TEST_HOME:-}" && ! -d "$XDG_CACHE_HOME" ]]; then\n'
                      '  echo "FAIL: fresh Linux cache directory missing" >&2; exit 1\n'
                      'fi\nengine_log=""\nwhile (( $# )); do\n'
                      '  if [[ "$1" == --log-file ]]; then engine_log="$2"; break; fi\n'
                      '  if [[ "$1" == -- ]]; then break; fi\n'
                      '  shift\ndone\n'
                      'printf "synthetic engine file log\\n" > "${engine_log:-$FED_TEST_PLAYER_LOG}"\n'
                      'cat "$FED_TEST_LOG"\nexit "$FED_TEST_EXIT"\n')
    engine.chmod(0o755)
    platform = tools / 'uname'
    platform.write_text('#!/bin/sh\nprintf "Linux\\n"\n')
    platform.chmod(0o755)
    for command in ('lipo', 'codesign'):
        tripwire = tools / command
        tripwire.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$0" >> "$FED_TEST_DOWNSTREAM"\nexit 73\n')
        tripwire.chmod(0o755)
    log = temporary / 'engine-output.log'
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                       RUNNER_TEMP=directory, FED_TEST_LOG=str(log))
    player_log = temporary / 'player-crash.log'
    environment['FED_TEST_PLAYER_LOG'] = str(player_log)
    for index, (marker, exit_code) in enumerate((('', 0), ('SCRIPT ERROR:', 0), ('ERROR:', 0), ('FAIL:', 0), ('', 42))):
        trace = temporary / f'downstream-{index}'
        environment['FED_TEST_DOWNSTREAM'] = str(trace)
        environment['FED_TEST_EXIT'] = str(exit_code)
        rejected = bool(marker or exit_code)
        log.write_text((marker + ' synthetic runtime failure\n' if marker else '')
                       + 'PASS: isolated Godot user storage verified before fixture writes; synthetic output only\n'
                       + 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\n'
                       + guidance_marker + '\n'
                       + mandate_marker + '\n'
                       + music_marker + '\n'
                       + 'PASS: comparison count, exact parity and paired timing fixture; synthetic output only\n')
        log.write_text(log.read_text()
                       + 'COUNTS mode=pilot attempted=7 completed=7 transitions=168 paired=3 failures=0\n'
                       + 'PASS: current-source curated career diagnostic pilot\n'
                       + 'COUNTS mode=full attempted=1100 completed=1100 transitions=264000 paired=100 failures=0\n'
                       + 'PASS: current-source curated career diagnostic full\n')
        for script, arguments in (('scripts/test-model.sh', []), ('scripts/test-game.sh', []),
                                  ('scripts/test-curated-careers.sh', ['pilot']), ('scripts/test-curated-careers.sh', ['full'])):
            player_log.write_text('preserved player crash evidence')
            result = subprocess.run(['bash', str(root / script), *arguments], env=environment,
                                    capture_output=True, text=True)
            assert player_log.read_text() == 'preserved player crash evidence', f'{script}: engine file logger touched player evidence'
            if (result.returncode != 0) != rejected:
                failures.append(f'{script}: wrong result for {marker or "clean output"}, exit {exit_code}')
        player_log.write_text('preserved player crash evidence')
        result = subprocess.run(ci_shell + ['-c', '\n'.join(ci_import + ci_commands)], env=environment, cwd=root,
                                capture_output=True, text=True)
        assert player_log.read_text() == 'preserved player crash evidence', 'CI engine file logger touched player evidence'
        if (result.returncode != 0) != rejected:
            failures.append(f'CI verification: wrong result for {marker or "clean output"}, exit {exit_code}')
        if rejected:
            player_log.write_text('preserved player crash evidence')
            result = subprocess.run(['bash', str(root / 'scripts/package-game.sh'),
                                     str(temporary / f'export-{index}'), 'unused identity', 'unused team'],
                                    env=environment, capture_output=True, text=True)
            assert player_log.read_text() == 'preserved player crash evidence', 'packager engine file logger touched player evidence'
            if result.returncode == 0 or trace.exists():
                failures.append(f'packager continued past {marker} before thinning/signing')
    # A generic PASS cannot certify the fresh-process music preference check.
    log.write_text(log.read_text().replace(music_marker + '\n', ''))
    environment['FED_TEST_EXIT'] = '0'
    incomplete_music = subprocess.run(['bash', str(root / 'scripts/test-game.sh'), 'music_test'],
                                      env=environment, capture_output=True, text=True)
    assert incomplete_music.returncode != 0, 'music wrapper must require its relaunch completion marker'
    # Earlier completion markers cannot certify the bundled mandate path.
    environment['FED_TEST_EXIT'] = '0'
    for label, completion in incomplete_completions:
        log.write_text(completion)
        result = subprocess.run(ci_shell + ['-c', '\n'.join(ci_commands)],
                                env=environment, cwd=root, capture_output=True, text=True)
        if result.returncode == 0:
            failures.append(f'CI verification accepts incomplete completion: {label}')
    # A generic PASS cannot certify completion of the additional comparison fixture.
    log.write_text('PASS: isolated Godot user storage verified before fixture writes; synthetic output only\n'
                   + music_marker + '\n'
                   + 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\n')
    environment['FED_TEST_EXIT'] = '0'
    incomplete = subprocess.run(['bash', str(root / 'scripts/test-game.sh')],
                                env=environment, capture_output=True, text=True)
    assert incomplete.returncode != 0, 'comparison wrapper must require its own completion marker'
if failures:
    raise AssertionError('\n'.join(failures))
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
    release_output = 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\n' + guidance_marker + '\n' + mandate_marker + '\n'
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
            text = release_output
        return subprocess.CompletedProcess(command, 0, text, '')
    with patch.dict(os.environ, HOME=str(home)), patch('sys.argv', ['verify-game-release.py', str(app), 'TESTTEAM']), patch('subprocess.run', side_effect=fake_release_tool):
        runpy.run_path(str(root / 'scripts/tests/verify-game-release.py'), run_name='__main__')
        assert os.environ['HOME'] == str(home), 'release check must preserve parent HOME'
        for label, completion in incomplete_completions:
            release_output = completion
            rejected = False
            try:
                runpy.run_path(str(root / 'scripts/tests/verify-game-release.py'), run_name='__main__')
            except (AssertionError, ValueError):
                rejected = True
            assert rejected, f'Native release verifier accepts incomplete completion: {label}'
    assert engine_homes and all(path != home for path in engine_homes), 'release check must isolate engine HOME'
    assert protected.read_text() == 'player crash evidence', 'release check must preserve player logs'
print('PASS: release self-check preserves player userdata (simulated engine writes)')


# Execute the real verifier in fresh optimized interpreters; the fixture tools
# replace every subprocess, so no native executable or signing tool can launch.
import sys
release_fixture = r"""
import os, plistlib, runpy, subprocess, sys
from pathlib import Path
from unittest.mock import patch
app = Path(sys.argv[2])
case = sys.argv[3]
embedded_headers = {'embedded_mh32_be': 'feedface', 'embedded_mh32_le': 'cefaedfe',
                    'embedded_fat64_be': 'cafebabf', 'embedded_fat64_le': 'bfbafeca'}
(app / 'Contents/Resources/native.so').write_bytes(bytes.fromhex(embedded_headers.get(case, 'cffaedfe')))
info = {'CFBundleExecutable': 'candidate', 'CFBundleIdentifier': 'local.fed-chairman-game.policy-lab'}
if case == 'bundle': info['CFBundleIdentifier'] = 'wrong.bundle'
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
log = 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city\nPASS: bundled guidance continuation and comparison\nPASS: bundled mandate assessment and realized feedback\n'
for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:'):
    if case == marker: log += marker + ' zero-exit failure\n'
for label, marker in (('baseline', 'PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city'), ('guidance', 'PASS: bundled guidance continuation and comparison'), ('mandate', 'PASS: bundled mandate assessment and realized feedback')):
    if case == label: log = log.replace(marker + '\n', '')
    if case == label + '_suffix': log = log.replace(marker + '\n', marker + '; incomplete\n')
signature = 'TeamIdentifier=TESTTEAM\nAuthority=Developer ID Application: Fixture\n(runtime)\nTimestamp=fixture\n'
for label, marker in (('team', 'TeamIdentifier=TESTTEAM'), ('authority', 'Authority=Developer ID Application:'), ('runtime', '(runtime)'), ('timestamp', 'Timestamp=')):
    if case == label: signature = signature.replace(marker, 'invalid')
def fake(command, **kwargs):
    output = ''
    if command[0] == 'lipo':
        output = 'arm64\n'
        if case == 'architecture' or (case.startswith('embedded_') and command[-1].endswith('native.so')): output = 'x86_64\n'
    elif command[0] == 'codesign' and '-d' in command: output = signature
    elif '--headless' in command: output = log
    return subprocess.CompletedProcess(command, 0, output, '')
verifier = sys.argv[1]
with patch('sys.argv', [verifier, str(app), 'TESTTEAM']), patch('subprocess.run', side_effect=fake):
    runpy.run_path(verifier, run_name='__main__')
"""
release_cases = ('clean', 'architecture', 'embedded_architecture', 'bundle', 'team', 'authority',
                 'runtime', 'timestamp', 'baseline', 'guidance', 'mandate', 'baseline_suffix',
                 'guidance_suffix', 'mandate_suffix', 'SCRIPT ERROR:', 'ERROR:', 'FAIL:',
                 'embedded_mh32_be', 'embedded_mh32_le', 'embedded_fat64_be', 'embedded_fat64_le')
release_failures = []
with tempfile.TemporaryDirectory(prefix='fed-optimized-release-') as directory:
    app = Path(directory) / 'Fixture.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Resources').mkdir()
    (app / 'Contents/MacOS/candidate').write_bytes(b'\xcf\xfa\xed\xfe')
    (app / 'Contents/Resources/native.so').write_bytes(b'\xcf\xfa\xed\xfe')
    for mode, flags, optimize in (('normal', [], ''), ('-O', ['-O'], ''), ('PYTHONOPTIMIZE=2', [], '2')):
        for case in release_cases:
            env = dict(os.environ)
            env.pop('PYTHONOPTIMIZE', None)
            if optimize: env['PYTHONOPTIMIZE'] = optimize
            result = subprocess.run([sys.executable, *flags, '-c', release_fixture,
                                     str(root / 'scripts/tests/verify-game-release.py'), str(app), case],
                                    env=env, capture_output=True, text=True)
            if (result.returncode == 0) != (case == 'clean'):
                release_failures.append(f'{mode}: unexpected release acceptance for {case}, exit={result.returncode}')
            if case != 'clean' and 'PASS: ARM64-only' in result.stdout:
                release_failures.append(f'{mode}: final PASS printed for {case}')
print(f'COUNTS release_gate_cases={len(release_cases) * 3} failures={len(release_failures)}')

# An invalid toolchain must fail before even exporting or reaching lipo/codesign.
with tempfile.TemporaryDirectory(prefix='fed-toolchain-package-') as directory:
    temporary = Path(directory)
    tools = temporary / 'bin'
    tools.mkdir()
    engine = tools / 'godot'
    engine.write_text('#!/bin/sh\nif [ "$1" = --version ]; then printf "%s\\n" "$FED_FAKE_VERSION"; exit 0; fi\nprintf "export\\n" >> "$FED_TEST_DOWNSTREAM"\n')
    engine.chmod(0o755)
    for command in ('lipo', 'codesign', 'ditto'):
        tool = tools / command
        tool.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$FED_TEST_DOWNSTREAM"\nexit 73\n')
        tool.chmod(0o755)
    for index, version in enumerate(('4.6.stable.official.fixture', '4.7.2.stable.official.fixture')):
        trace = temporary / f'trace-{index}'
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], HOME=str(temporary),
                   FED_FAKE_VERSION=version, FED_TEST_DOWNSTREAM=str(trace))
        result = subprocess.run(['bash', str(root / 'scripts/package-game.sh'), str(temporary / f'output-{index}'),
                                 'fixture identity', 'TESTTEAM'], env=env, capture_output=True, text=True)
        if result.returncode == 0 or trace.exists():
            release_failures.append(f'packager reached export/signing with unverified engine {version}')
helper = root / 'scripts/tests/verify-godot-toolchain.py'
if not helper.exists():
    release_failures.append('official byte-pin verifier is missing')
else:
    import hashlib
    import shutil
    helper_globals = runpy.run_path(str(helper), run_name='toolchain_fixture')
    verify = helper_globals['verify']
    globals_ = verify.__globals__
    # The vendor archive chain is independent evidence; fixtures test byte pins
    # without requiring a disposable installer cache on every packaging run.
    with tempfile.TemporaryDirectory(prefix='fed-toolchain-pins-') as directory:
        temporary = Path(directory)
        engine = temporary / 'godot'
        engine.write_bytes(b'fixture-engine-original')
        template = temporary / 'macos.zip'
        template.write_bytes(b'fixture-official-template')
        engine_hash = hashlib.sha256(engine.read_bytes()).hexdigest()
        template_hash = hashlib.sha256(template.read_bytes()).hexdigest()
        assert not (temporary / 'Library/Caches/Homebrew/Cask/godot--4.7.2.zip').exists()
        cases = ('clean_without_installer', 'version', 'engine', 'template', 'missing_template')
        for case in cases:
            engine.write_bytes(b'fixture-engine-original' if case != 'engine' else b'custom-engine')
            template.write_bytes(b'fixture-official-template' if case != 'template' else b'custom-template')
            selected_template = temporary / 'missing-template.zip' if case == 'missing_template' else template
            output = '4.6.stable.official.fixture\n' if case == 'version' else '4.7.2.stable.official.fixture\n'
            with patch.dict(globals_, ENGINE_SHA256=engine_hash, MACOS_TEMPLATE_SHA256=template_hash), \
                    patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0, output, '')):
                rejected = False
                try:
                    verify(engine, selected_template)
                except TypeError as error:
                    release_failures.append(f'Byte-pin verifier still requires installer API: {case}: {error}')
                    rejected = True
                except (ValueError, FileNotFoundError):
                    rejected = True
                if rejected != (case != 'clean_without_installer'):
                    release_failures.append(f'Official byte-pin verifier wrong result: {case}')
        print(f'COUNTS toolchain_pin_cases={len(cases)}')
    # Exercise the real packaging shell with synthetic expected hashes in a
    # private helper copy. Wrong version/engine/template must stop before export.
    with tempfile.TemporaryDirectory(prefix='fed-toolchain-tripwire-') as directory:
        temporary = Path(directory)
        fixture_root = temporary / 'source'
        (fixture_root / 'scripts/tests').mkdir(parents=True)
        (fixture_root / 'game').mkdir()
        shutil.copy2(root / 'scripts/package-game.sh', fixture_root / 'scripts/package-game.sh')
        shutil.copy2(root / 'game/export_presets.cfg', fixture_root / 'game/export_presets.cfg')
        home = temporary / 'home'
        template = home / 'Library/Application Support/Godot/export_templates/4.7.2.stable/macos.zip'
        template.parent.mkdir(parents=True)
        template_bytes = b'synthetic matching template'
        tools = temporary / 'bin'
        tools.mkdir()
        engine = tools / 'godot'
        engine_text = '#!/bin/sh\nif [ "$1" = --version ]; then printf "%s\\n" "$FED_FAKE_VERSION"; exit 0; fi\nprintf "export\\n" >> "$FED_TEST_DOWNSTREAM"\nprintf "%s\\n" "$FED_FAKE_EXPORT_LOG"\nexit "$FED_FAKE_EXPORT_EXIT"\n'
        engine.write_text(engine_text)
        engine.chmod(0o755)
        for command in ('lipo', 'codesign', 'ditto'):
            tripwire = tools / command
            tripwire.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$FED_TEST_DOWNSTREAM_NATIVE"\nexit 73\n')
            tripwire.chmod(0o755)
        synthetic_engine_hash = hashlib.sha256(engine.read_bytes()).hexdigest()
        synthetic_template_hash = hashlib.sha256(template_bytes).hexdigest()
        helper_text = helper.read_text()
        for name, value in (('ENGINE_SHA256', synthetic_engine_hash), ('MACOS_TEMPLATE_SHA256', synthetic_template_hash)):
            helper_text = '\n'.join(f"{name} = '{value}'" if line.startswith(name + ' = ') else line for line in helper_text.split('\n'))
        (fixture_root / 'scripts/tests/verify-godot-toolchain.py').write_text(helper_text)
        assert not (home / 'Library/Caches/Homebrew/Cask/godot--4.7.2.zip').exists()
        package_cases = ('clean_without_installer', 'version', 'engine', 'template')
        for index, case in enumerate(package_cases):
            engine.write_text(engine_text + ('# custom bytes\n' if case == 'engine' else ''))
            template.write_bytes(b'custom template' if case == 'template' else template_bytes)
            trace = temporary / f'trace-{index}'
            downstream = temporary / f'native-{index}'
            version = '4.6.stable.official.fixture' if case == 'version' else '4.7.2.stable.official.fixture'
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], HOME=str(home),
                       FED_FAKE_VERSION=version, FED_TEST_DOWNSTREAM=str(trace),
                       FED_TEST_DOWNSTREAM_NATIVE=str(downstream), FED_FAKE_EXPORT_LOG='synthetic export',
                       FED_FAKE_EXPORT_EXIT='73')
            result = subprocess.run(['bash', str(fixture_root / 'scripts/package-game.sh'), str(temporary / f'output-{index}'),
                                     'fixture identity', 'TESTTEAM'], env=env, capture_output=True, text=True)
            exported = trace.exists() and trace.read_text() == 'export\n'
            if exported != (case == 'clean_without_installer') or (exported and result.returncode != 73) or downstream.exists():
                release_failures.append(f'Packager byte-pin/version boundary wrong result: {case}: {result.stderr}')
        print(f'COUNTS toolchain_package_cases={len(package_cases)}')
        engine.write_text(engine_text)
        template.write_bytes(template_bytes)
        export_cases = (('SCRIPT ERROR:', 0), ('ERROR:', 0), ('FAIL:', 0), ('', 42))
        for index, (error_marker, exit_code) in enumerate(export_cases):
            trace = temporary / f'export-trace-{index}'
            downstream = temporary / f'export-native-{index}'
            output = temporary / f'export-output-{index}'
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], HOME=str(home),
                       FED_FAKE_VERSION='4.7.2.stable.official.fixture', FED_TEST_DOWNSTREAM=str(trace),
                       FED_TEST_DOWNSTREAM_NATIVE=str(downstream), FED_FAKE_EXPORT_LOG=error_marker + ' synthetic export',
                       FED_FAKE_EXPORT_EXIT=str(exit_code))
            result = subprocess.run(['bash', str(fixture_root / 'scripts/package-game.sh'), str(output),
                                     'fixture identity', 'TESTTEAM'], env=env, capture_output=True, text=True)
            exported = trace.exists() and trace.read_text() == 'export\n'
            verified = (output / 'toolchain.log').exists() and 'PASS: official Godot toolchain' in (output / 'toolchain.log').read_text()
            logged = (output / 'export.log').exists() and error_marker + ' synthetic export' in (output / 'export.log').read_text()
            if result.returncode == 0 or not exported or not verified or not logged or downstream.exists():
                release_failures.append(f'Export boundary reached thinning/signing or skipped export: {error_marker or "nonzero exit"}, exit={result.returncode}, downstream={downstream.exists()}')
            print(f'EXPORT_BOUNDARY marker={error_marker or "nonzero exit"!r} process_exit={result.returncode} export_reached={exported} downstream_reached={downstream.exists()}')
        print(f'COUNTS export_error_cases={len(export_cases)}')

if release_failures:
    raise AssertionError('\n'.join(release_failures))
print('PASS: optimized release gates and cache-independent official byte pins (synthetic tools only)')
