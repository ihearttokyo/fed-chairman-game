"""Validate an actual Apple Silicon Developer ID release, without changing it."""
from pathlib import Path
import os
import plistlib
import subprocess
import sys
import tempfile

app = Path(sys.argv[1]).resolve(strict=True)
team = sys.argv[2]
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
binary = app / 'Contents/MacOS' / info['CFBundleExecutable']

def run(*args, env=None):
    result = subprocess.run(args, capture_output=True, text=True, check=True, timeout=120, env=env)
    return result.stdout + result.stderr

for path in (app / 'Contents').rglob('*'):
    if path.is_file():
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic in (b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
            assert run('lipo', '-archs', str(path)).strip() == 'arm64', 'Release must be ARM64-only'
assert run('lipo', '-archs', str(binary)).strip() == 'arm64', 'Release must be ARM64-only'
assert info['CFBundleIdentifier'] == 'local.fed-chairman-game.policy-lab'
run('codesign', '--verify', '--strict', '--verbose=2', str(app))
signature = run('codesign', '-d', '--verbose=4', str(app))
assert f'TeamIdentifier={team}\n' in signature, 'Unexpected signing team'
assert 'Authority=Developer ID Application:' in signature, 'Developer ID signature required'
assert '(runtime)' in signature, 'Hardened runtime required'
assert 'Timestamp=' in signature, 'Secure timestamp required'
# Preserve player saves and crash logs while executing the exact release binary.
with tempfile.TemporaryDirectory(prefix='fed-release-check-') as home:
    log = run(str(binary), '--headless', '--quit-after', '600', '--', '--verify-build',
              env=dict(os.environ, HOME=home))
assert not any(marker in log for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')), log
assert 'PASS: 164 release-safe checks' in log, log
print(log.strip())
print('PASS: ARM64-only, Developer ID, hardened runtime, timestamp and strict signature')
