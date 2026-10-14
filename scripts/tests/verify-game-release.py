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

def require(condition, message):
    if not condition:
        raise ValueError(message)

for path in (app / 'Contents').rglob('*'):
    if path.is_file():
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic in (b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
                    b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'):
            require(run('lipo', '-archs', str(path)).strip() == 'arm64', 'Release must be ARM64-only')
require(run('lipo', '-archs', str(binary)).strip() == 'arm64', 'Release must be ARM64-only')
require(info['CFBundleIdentifier'] == 'local.fed-chairman-game.policy-lab', 'Unexpected bundle identifier')
run('codesign', '--verify', '--strict', '--verbose=2', str(app))
signature = run('codesign', '-d', '--verbose=4', str(app))
require(f'TeamIdentifier={team}\n' in signature, 'Unexpected signing team')
require('Authority=Developer ID Application:' in signature, 'Developer ID signature required')
require('(runtime)' in signature, 'Hardened runtime required')
require('Timestamp=' in signature, 'Secure timestamp required')
# Preserve player saves and crash logs while executing the exact release binary.
with tempfile.TemporaryDirectory(prefix='fed-release-check-') as home:
    log = run(str(binary), '--headless', '--quit-after', '600', '--', '--verify-build',
              env=dict(os.environ, HOME=home))
require(not any(marker in log for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')), log)
require('PASS: 187 release-safe checks; eight 20-quarter careers, lossless replay, main scene and city' in log.splitlines(), log)
require('PASS: bundled guidance continuation and comparison' in log.splitlines(), log)
require('PASS: bundled mandate assessment and realized feedback' in log.splitlines(), log)
print(log.strip())
print('PASS: ARM64-only, Developer ID, hardened runtime, timestamp and strict signature')
