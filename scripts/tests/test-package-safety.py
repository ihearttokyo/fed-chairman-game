"""Godot is the only build path and refuses replacement before any app action."""
from pathlib import Path
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
