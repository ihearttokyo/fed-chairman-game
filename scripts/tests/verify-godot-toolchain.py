"""Bind the packaging engine and macOS template to official Godot release bytes."""
from pathlib import Path
import configparser
import hashlib
import subprocess
import sys

# https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable
# Godot.app/Contents/MacOS/Godot from official macOS ZIP SHA256 c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e.
ENGINE_SHA256 = 'c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf'
# templates/macos.zip from official TPZ SHA256 f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011.
MACOS_TEMPLATE_SHA256 = '88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792'

def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(chunk)
    return result.hexdigest()

def verify(engine, template):
    with engine.open('rb') as stream:
        if digest(stream) != ENGINE_SHA256:
            raise ValueError('Resolved Godot engine differs from the official 4.7.2 engine bytes')
    with template.open('rb') as stream:
        if digest(stream) != MACOS_TEMPLATE_SHA256:
            raise ValueError('Installed macOS export template differs from the official 4.7.2 template')
    version = subprocess.run([str(engine), '--version'], capture_output=True, text=True,
                             check=True, timeout=30).stdout.strip()
    if not version.startswith('4.7.2.stable.official.'):
        raise ValueError(f'Packaging requires official Godot 4.7.2, got {version!r}')
    print(f'PASS: official Godot toolchain {version}; engine SHA256={ENGINE_SHA256}; '
          f'macOS template SHA256={MACOS_TEMPLATE_SHA256}')

if __name__ == '__main__':
    engine = Path(sys.argv[1]).resolve(strict=True)
    if any((engine.parent / name).exists() for name in ('_sc_', '._sc_')):
        raise ValueError('Self-contained Godot template lookup is not supported for packaging')
    presets = configparser.ConfigParser()
    presets.read(Path(__file__).resolve().parents[2] / 'game/export_presets.cfg')
    if presets.get('preset.0', 'name') != '"macOS universal staging"':
        raise ValueError('Unexpected release export preset')
    if presets.get('preset.0.options', 'custom_template/release', fallback='').strip('"'):
        raise ValueError('Custom release templates are not supported for packaging')
    home = Path.home()
    verify(engine, home / 'Library/Application Support/Godot/export_templates/4.7.2.stable/macos.zip')
