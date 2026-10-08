"""Regenerate the policy workbook in a new external directory, without installs."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CASES = ('base', 'demand_boom', 'supply_shock', 'funding_stress',
         'unanchored_inflation', 'lower_bound_slump', 'mixed_crises')
BUILD_PHASES = ('main', 'hold', 'responsive')


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
    if '--headless' in command:
        command = [command[0], '--log-file', str(log_path.with_suffix('.engine.log')), *command[1:]]
    with log_path.open('x') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                text=True, timeout=900)
    text = log_path.read_text()
    if result.returncode or any(marker in text for marker in ('SCRIPT ERROR:', 'ERROR:', 'FAIL:')):
        raise ValueError(f'Tool failed; inspect {log_path}')
    if completion not in text:
        raise ValueError(f'Tool did not report completion; inspect {log_path}')


def validated_portfolio(path):
    raw = path.read_bytes()
    reference = json.loads(raw)
    weights = reference.get('treasury_maturity_weights', [])
    if (reference.get('schema_version') != 1 or len(weights) != 120
            or any(type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in weights)
            or abs(sum(weights) - 1) > 1e-12):
        raise ValueError('Invalid source-bound Treasury maturity ladder')
    principal = float(reference['source_treasury_principal_usd'])
    if not math.isfinite(principal) or principal <= 0:
        raise ValueError('Invalid source Treasury principal')
    for key in ('mbs_monthly_principal_billion_usd', 'mbs_stock_billion_usd',
                'market_treasury_wam_years', 'treasury_duration_years', 'mbs_duration_years'):
        value = reference.get(key)
        if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
            raise ValueError(f'Invalid portfolio observation: {key}')
    return reference, hashlib.sha256(raw).hexdigest()


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
    portfolio_path = ROOT / 'game/model/portfolio_reference.json'
    portfolio, portfolio_hash = validated_portfolio(portfolio_path)
    output.mkdir(parents=True)  # Atomic reservation; an existing destination is never reused.
    references = output / 'reference-v1'
    evidence = output / 'evidence'
    references.mkdir()
    evidence.mkdir()
    (output / 'node_modules').symlink_to(args.modules.resolve(), target_is_directory=True)
    builder = ROOT / 'scripts/spreadsheet/build-policy-lab.mjs'
    execution_copy = output / builder.name
    shutil.copyfile(builder, execution_copy)
    shutil.copyfile(portfolio_path, references / 'portfolio-reference.json')
    (references / 'portfolio-reference.sha256').write_text(portfolio_hash + '\n')
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
    run_tool([str(args.godot), '--headless', '--path', str(ROOT / 'game'),
              '--script', 'res://tests/export_policy_variants.gd', '--', '--output',
              str(references / 'rate-boundaries.json'), '--rate-boundaries'],
             evidence / 'rate-boundaries.log', 'EXPORTED seven signed-rate boundary traces')
    run_tool([str(args.godot), '--headless', '--path', str(ROOT / 'game'),
              '--script', 'res://tests/export_policy_variants.gd', '--', '--output',
              str(references / 'balance-boundaries.json'), '--balance-boundaries'],
             evidence / 'balance-boundaries.log', 'EXPORTED fifteen balance-sheet boundary traces')
    run_tool([str(args.godot), '--headless', '--path', str(ROOT / 'game'),
              '--script', 'res://tests/export_late_checkpoint_reference.gd', '--', '--output',
              str(references / 'late-checkpoints.json')],
             evidence / 'late-checkpoints.log', 'EXPORTED six full-state late checkpoint segments')
    checkpoints = json.loads((references / 'late-checkpoints.json').read_text())
    if len(checkpoints) != 6:
        raise ValueError('Expected six late checkpoint segments')
    for i, record in enumerate(checkpoints):
        branch = 'hold' if i < 3 else 'responsive'
        start, end = ((120, 168), (168, 216), (216, 240))[i % 3]
        name = f'late_{branch}_{start}_{end}'
        if record['name'] != name or len(record['quarters']) != end - start:
            raise ValueError('Invalid late checkpoint name/horizon')
        for source_path, source_hash in record['source_sha256'].items():
            if hashlib.sha256((ROOT / 'game' / source_path).read_bytes()).hexdigest() != source_hash:
                raise ValueError(f'Late checkpoint source changed: {source_path}')
        with (references / f'{name}.json').open('x') as destination:
            json.dump(record, destination, indent=2)
    for path in references.glob('*.json'):
        if path.name == 'portfolio-reference.json':
            continue
        document = json.loads(path.read_text())
        for record in document if isinstance(document, list) else [document]:
            if record.get('portfolio_reference_json') != portfolio_path.read_text() or json.loads(record['portfolio_reference_json']) != portfolio or record.get('portfolio_reference_sha256') != portfolio_hash:
                raise ValueError(f'Native reference source binding mismatch: {path.name}')
    run_tool([str(args.node), str(ROOT / 'scripts/tests/test-workbook-validation.mjs'),
              '--checkpoint-reference', str(references / 'late-checkpoints.json')],
             evidence / 'checkpoint-input-contract.log', 'PASS: full-state checkpoint input contract')
    parity = []
    for phase in BUILD_PHASES:
        run_tool([str(args.node), str(execution_copy), '--phase', phase],
                 evidence / f'workbook-build-{phase}.log', f'COMPLETED workbook phase {phase}')
        phase_checks = json.loads((evidence / f'workbook-parity-{phase}.json').read_text())
        if phase == 'main' and (
                [record['case'] for record in phase_checks if 'case' in record] != list(CASES)
                or any(sum(key in record for record in phase_checks) != count
                       for key, count in {'policyEdit': 4, 'priceBoundary': 3,
                                          'rateBoundary': 7, 'balanceBoundary': 15}.items())
                or any('checkpoint' in record for record in phase_checks)):
            raise ValueError('Incomplete main workbook checks')
        if phase != 'main' and [record.get('checkpoint') for record in phase_checks] != [
                record['name'] for record in checkpoints if record['policy_kind'] == phase]:
            raise ValueError(f'Incomplete checkpoint phase: {phase}')
        parity.extend(phase_checks)
    run_tool([sys.executable, str(ROOT / 'scripts/spreadsheet/check-workbook.py'),
              str(output / 'Federal Reserve Policy Lab.xlsx'), '--reference',
              str(references / 'supply_shock.json'), '--map',
              str(evidence / 'workbook-model-map.json'), '--campaign-reference',
              str(references / 'mixed_crises.json'), '--portfolio-reference',
              str(references / 'portfolio-reference.json')],
             evidence / 'workbook-export-check.log', 'PASS ')
    run_tool([sys.executable, str(ROOT / 'scripts/tests/test-workbook-file.py'),
              str(output / 'Federal Reserve Policy Lab.xlsx'),
              str(references / 'supply_shock.json'), str(evidence / 'workbook-model-map.json'),
              str(references / 'mixed_crises.json')],
             evidence / 'workbook-file-regression.log', 'PASS: real workbook accepted')
    for record in checkpoints:
        name = record['name']
        run_tool([sys.executable, str(ROOT / 'scripts/spreadsheet/check-workbook.py'),
                  str(output / 'late-checkpoints' / f'{name}.xlsx'), '--reference',
                  str(references / f'{name}.json'), '--map',
                  str(evidence / 'workbook-model-map.json'), '--portfolio-reference',
                  str(references / 'portfolio-reference.json')],
                 evidence / f'checkpoint-{name}.log', 'PASS ')
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest(builder) == digest(execution_copy), 'Execution copy differs from source'
    with (evidence / 'workbook-parity.json').open('x') as destination:
        json.dump(parity, destination, indent=2)
    provenance = {
        'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'portfolio_reference_sha256': portfolio_hash,
        'godot_version': version, 'builder_sha256': digest(builder),
        'build_phases': list(BUILD_PHASES),
        'node_version': subprocess.check_output([str(args.node), '--version'], text=True).strip(),
        'source_sha256': {name: digest(ROOT / name) for name in (
            'scripts/build-workbook.py', 'scripts/spreadsheet/build-policy-lab.mjs',
            'scripts/spreadsheet/check-workbook.py', 'scripts/tests/test-workbook-validation.mjs', 'game/tests/export_reference.gd',
            'game/tests/export_policy_variants.gd', 'game/tests/export_late_checkpoint_reference.gd',
            'scripts/tests/test-workbook-file.py')},
        'workbook_sha256': digest(output / 'Federal Reserve Policy Lab.xlsx'),
        'checkpoint_workbooks_sha256': {path.name: digest(path) for path in sorted((output / 'late-checkpoints').glob('*.xlsx'))},
        'model_sha256': {name: digest(ROOT / 'game/model' / name)
                         for name in ('economy.gd', 'parameters.json', 'scenarios.json', 'exogenous_shocks.json', 'portfolio_reference.json')},
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
