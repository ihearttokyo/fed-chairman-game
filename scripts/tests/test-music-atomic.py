"""Inject a child-only file-size limit; never fill the disk or touch player data."""
from pathlib import Path
import hashlib
import json
import os
import resource
import signal
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
engine = sys.argv[1:]
if not engine:
    raise SystemExit('Pass the existing Godot executable command')
home = Path(tempfile.mkdtemp(prefix='fed-game-home.', dir='/tmp')).resolve()
for child in ('tmp', '.cache', 'Library/Caches', '.local/share', '.config'):
    (home / child).mkdir(parents=True, exist_ok=True)
userdata = home / ('Library/Application Support' if sys.platform == 'darwin' else '.local/share') / 'FedChairmanPolicyLab'
userdata.mkdir(parents=True, exist_ok=True)
settings = userdata / 'policy-lab-audio-v1.cfg'
original = ('[audio]\nmusic_enabled=false\n\n[other]\nsentinel="' + 'x' * 262144 + '"\n').encode()
settings.write_bytes(original)
env = dict(os.environ, HOME=str(home), FED_GAME_TEST_HOME=str(home), TMPDIR=str(home / 'tmp'),
           XDG_CACHE_HOME=str(home / '.cache'), XDG_DATA_HOME=str(home / '.local/share'),
           XDG_CONFIG_HOME=str(home / '.config'), FED_MUSIC_FIXTURE_SHA256=hashlib.sha256(original).hexdigest())

def limit_child():
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
    resource.setrlimit(resource.RLIMIT_FSIZE, (65536, 65536))

command = engine + ['--headless', '--max-fps', '60', '--path', str(root / 'game'),
                    '--log-file', str(home / 'engine.log'), '--script', 'res://tests/music_atomic_test.gd',
                    '--quit-after', '1800']
result = subprocess.run(command, env=env, cwd=root, capture_output=True, timeout=60, preexec_fn=limit_child)
(home / 'stdout.log').write_bytes(result.stdout)
(home / 'stderr.log').write_bytes(result.stderr)
raw = (result.stdout + result.stderr).decode(errors='replace')
pending = sorted(str(path) for path in userdata.glob(settings.name + '.pending*'))
valid = (result.returncode == 0 and settings.read_bytes() == original and not pending
         and 'PASS: native size-limited preference update preserves the previous file and reports failure' in raw.splitlines()
         and not any(marker in raw for marker in ('ERROR:', 'FAIL:', 'leaked at exit')))
(home / 'receipt.json').write_text(json.dumps(dict(result='PASS' if valid else 'FAIL', returncode=result.returncode,
                                                 previous_file_unchanged=settings.read_bytes() == original,
                                                 limit_bytes=65536, pending_residue=pending, command=command), indent=2) + '\n')
print(f'ATOMIC_TEST_HOME: {home} (raw logs retained)')
if not valid:
    print(raw, file=sys.stderr)
    raise SystemExit(1)
print('PASS: native preference mid-write failure is isolated and preserves the prior file (child resource-limit fault injection)')
