"""Regenerate the policy workbook in a new external directory, without installs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CASES = ('base', 'demand_boom', 'supply_shock', 'funding_stress',
         'unanchored_inflation', 'lower_bound_slump')


def new_output(value):
    path = Path(value)
    if not path.is_absolute():
        raise ValueError('Output must be an absolute path')
    target = path.resolve()
    if path.exists() or path.is_symlink() or target.exists():
        raise ValueError('Refusing to replace existing output')
    for location in (path, target):
        if any((parent / '.git').exists() for parent in (location, *location.parents)):
            raise ValueError('Output must be outside all Git checkouts')
    return target


def run_tool(command, log_path, completion):
    with log_path.open('x') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                text=True, timeout=900)
    text = log_path.read_text()
    if result.returncode or any(marker in text for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')):
        raise ValueError(f'Tool failed; inspect {log_path}')
    if completion not in text:
        raise ValueError(f'Tool did not report completion; inspect {log_path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', help='new absolute directory outside Git')
    parser.add_argument('--node', required=True, type=Path, help='managed Node executable')
    parser.add_argument('--modules', required=True, type=Path, help='managed node_modules directory')
    parser.add_argument('--godot', default=shutil.which('godot'), type=Path)
    args = parser.parse_args()
    output = new_output(args.output)  # Refuse replacement before any tool invocation.
    for executable in (args.node, args.godot):
        if executable is None or not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError('Supply executable Node and Godot paths')
    if not args.modules.is_dir():
        raise ValueError('Supply the managed node_modules directory')
    args.node = args.node.resolve()
    args.godot = args.godot.resolve()
    version = subprocess.check_output([str(args.godot), '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable'):
        raise ValueError('Workbook reference paths require Godot 4.7.2')
    output.mkdir(parents=True)  # Atomic reservation; an existing destination is never reused.
    references = output / 'reference-v1'
    evidence = output / 'evidence'
    references.mkdir()
    evidence.mkdir()
    (output / 'node_modules').symlink_to(args.modules.resolve(), target_is_directory=True)
    builder = ROOT / 'scripts/spreadsheet/build-policy-lab.mjs'
    execution_copy = output / builder.name
    shutil.copyfile(builder, execution_copy)
    for case in CASES:
        run_tool([str(args.godot), '--headless', '--path', str(ROOT / 'game'),
                  '--script', 'res://tests/export_reference.gd', '--', '--output',
                  str(references / f'{case}.json'), '--scenario', case,
                  '--quarters', '48', '--seed', '1', '--policy', 'feedback'],
                 evidence / f'reference-{case}.log', 'EXPORTED ')
    run_tool([str(args.godot), '--headless', '--path', str(ROOT / 'game'),
              '--script', 'res://tests/export_policy_variants.gd', '--', '--output',
              str(references / 'policy-variants.json')],
             evidence / 'policy-variants.log', 'EXPORTED four one-variable policy traces')
    run_tool([str(args.godot), '--headless', '--path', str(ROOT / 'game'),
              '--script', 'res://tests/export_policy_variants.gd', '--', '--output',
              str(references / 'price-boundaries.json'), '--price-boundaries'],
             evidence / 'price-boundaries.log', 'EXPORTED three physical price boundary traces')
    run_tool([str(args.node), str(execution_copy)], evidence / 'workbook-build.log',
             'EXPORTED Federal Reserve Policy Lab.xlsx')
    run_tool([sys.executable, str(ROOT / 'scripts/spreadsheet/check-workbook.py'),
              str(output / 'Federal Reserve Policy Lab.xlsx'), '--reference',
              str(references / 'supply_shock.json'), '--map',
              str(evidence / 'workbook-model-map.json')],
             evidence / 'workbook-export-check.log', 'PASS ')
    run_tool([sys.executable, str(ROOT / 'scripts/tests/test-workbook-file.py'),
              str(output / 'Federal Reserve Policy Lab.xlsx'),
              str(references / 'supply_shock.json'), str(evidence / 'workbook-model-map.json')],
             evidence / 'workbook-file-regression.log', 'PASS: real workbook accepted')
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest(builder) == digest(execution_copy), 'Execution copy differs from source'
    provenance = {
        'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'godot_version': version, 'builder_sha256': digest(builder),
        'node_version': subprocess.check_output([str(args.node), '--version'], text=True).strip(),
        'source_sha256': {name: digest(ROOT / name) for name in (
            'scripts/build-workbook.py', 'scripts/spreadsheet/build-policy-lab.mjs',
            'scripts/spreadsheet/check-workbook.py', 'game/tests/export_reference.gd',
            'game/tests/export_policy_variants.gd', 'scripts/tests/test-workbook-file.py')},
        'workbook_sha256': digest(output / 'Federal Reserve Policy Lab.xlsx'),
        'model_sha256': {name: digest(ROOT / 'game/model' / name)
                         for name in ('economy.gd', 'parameters.json', 'scenarios.json')},
        'references_sha256': {path.name: digest(path) for path in sorted(references.glob('*.json'))},
        'native_recalculation': 'not performed by this command',
    }
    (evidence / 'build-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print(f'BUILT {output / "Federal Reserve Policy Lab.xlsx"}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
