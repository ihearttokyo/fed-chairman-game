"""The legacy packager must refuse replacement before any build or app action."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
script = root / 'native/FedChairmanGame/scripts/package-native-release-candidate.sh'
text = script.read_text()
assert 'rm -rf' not in text, 'Packager must not recursively delete prior builds or installed apps'
with tempfile.TemporaryDirectory(prefix='fed-package-guard-') as directory:
    target = Path(directory) / 'Fed Chairman Game.app'
    target.mkdir()
    sentinel = target / 'preserved'
    sentinel.write_text('existing build')
    result = subprocess.run(['bash', str(script)], env={**os.environ, 'FED_CHAIRMAN_NATIVE_RELEASE_ROOT': directory}, capture_output=True, text=True)
    assert result.returncode == 1 and 'Refusing to replace existing output' in result.stderr, result.stderr
    assert sentinel.read_text() == 'existing build'
    assert list(Path(directory).iterdir()) == [target], 'Guard must run before generation/build'
print('PASS: package replacement is refused without changing existing artifacts')

with tempfile.TemporaryDirectory(prefix='fed-godot-package-guard-') as directory:
    sentinel = Path(directory) / 'preserved'
    sentinel.write_text('existing output')
    result = subprocess.run(['bash', str(root / 'scripts/package-game.sh'), directory,
                             'unused identity', 'unused team'], capture_output=True, text=True)
    assert result.returncode == 1 and 'Refusing to replace existing output' in result.stderr, result.stderr
    assert sentinel.read_text() == 'existing output'
    assert list(Path(directory).iterdir()) == [sentinel]
print('PASS: Godot packager refuses existing output before export or signing')
