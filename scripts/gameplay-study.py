#!/usr/bin/env python3
"""Offline study records. Hashes bind files; they do not prove blinding or fun."""
import argparse
from datetime import datetime, timezone
import hashlib
import fcntl
import json
import math
import os
from pathlib import Path
import sys
import unicodedata

STAGES = ('prepared', 'choice', 'rating1', 'rating2', 'reveal', 'feedback')
MAX_BYTES = 16 * 1024 * 1024
ROOT = Path(__file__).resolve().parents[1]


def data(path):
    path = Path(path)
    if not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError('Missing or oversized input: ' + str(path))
    with path.open('rb') as stream:
        payload = stream.read(MAX_BYTES + 1)
    if len(payload) > MAX_BYTES:
        raise ValueError('Input grew beyond the file limit')
    return payload


def digest(path):
    return hashlib.sha256(data(path)).hexdigest()


def parse_json(payload):
    value = json.loads(payload)
    if not isinstance(value, dict):
        raise ValueError('Expected a JSON object')
    return value


def read_json(path):
    return parse_json(data(path))


def text(value):
    return isinstance(value, str) and bool(value.strip()) and len(value) <= 4000


def rater_id(value):
    return unicodedata.normalize('NFC', unicodedata.normalize('NFC', value.strip()).casefold())


def sha(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def valid_record(stage, record):
    if stage == 'choice':
        return (set(record) == {'plan', 'current_signal', 'expected_effect', 'reversal_condition'}
                and type(record['plan']) is int and 0 <= record['plan'] <= 7
                and all(text(record[key]) for key in ('current_signal', 'expected_effect', 'reversal_condition')))
    if stage in ('rating1', 'rating2'):
        return (set(record) == {'rater', 'signal', 'channel', 'reversal', 'reason'}
                and text(record['rater']) and text(record['reason'])
                and all(type(record[key]) is bool for key in ('signal', 'channel', 'reversal')))
    if stage == 'feedback':
        return (set(record) == {'agency', 'comprehensibility', 'repetition', 'confusion', 'arithmetic_seconds', 'continue_playing'}
                and all(type(record[key]) is int and 1 <= record[key] <= 7
                        for key in ('agency', 'comprehensibility', 'repetition', 'confusion'))
                and type(record['arithmetic_seconds']) in (int, float)
                and (type(record['arithmetic_seconds']) is int or math.isfinite(record['arithmetic_seconds']))
                and record['arithmetic_seconds'] >= 0
                and type(record['continue_playing']) is bool)
    return False


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def sync_record(stream, study, *, sync_parent=False):
    stream.flush()
    os.fsync(stream.fileno())
    sync_directory(study)
    if sync_parent:
        sync_directory(study.parent)
    if sys.platform == "darwin":
        fcntl.fcntl(stream.fileno(), fcntl.F_FULLFSYNC)


def store(study, stage, record, previous, *, sync_parent=False):
    envelope = {'schema': 'fed-study-record-v1', 'stage': stage, 'record': record,
                'previous': previous, 'utc': datetime.now(timezone.utc).isoformat()}
    payload = (json.dumps(envelope, indent=2, allow_nan=False) + '\n').encode()
    if len(payload) > MAX_BYTES:
        raise ValueError('Serialized record exceeds reader limit')
    # Persist quarantine before a stage can appear on disk.
    pending = study / '.incomplete'
    with pending.open('xb') as marker:
        sync_record(marker, study, sync_parent=sync_parent)
    # Exclusive creation keeps retries from replacing a choice or partial write.
    fd = os.open(study / (stage + '.json'), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(payload)
        sync_record(stream, study)
    # A lost unlink after power failure conservatively quarantines durable evidence.
    pending.unlink()


def state(study):
    if (study / '.incomplete').exists():
        raise ValueError('Incomplete study write; retain this trial and start a new one')
    records, previous = {}, {}
    gap = False
    for stage in STAGES:
        path = study / (stage + '.json')
        if not path.exists():
            gap = True
            continue
        if gap:
            raise ValueError('Missing predecessor before ' + stage)
        payload = data(path)
        envelope = parse_json(payload)
        if (envelope.get('schema') != 'fed-study-record-v1' or envelope.get('stage') != stage
                or envelope.get('previous') != previous or not isinstance(envelope.get('record'), dict)):
            raise ValueError('Changed record binding: ' + stage)
        record = envelope['record']
        if stage == 'prepared':
            for binding in record['inputs'].values():
                if digest(binding['path']) != binding['sha256']:
                    raise ValueError('Changed study input: ' + binding['path'])
        elif stage == 'reveal':
            if digest(record['path']) != record['sha256']:
                raise ValueError('Changed revealed result')
        elif not valid_record(stage, record):
            raise ValueError('Invalid stored record: ' + stage)
        records[stage] = record
        previous[stage + '.json'] = hashlib.sha256(payload).hexdigest()
    if not records:
        raise ValueError('Study is not prepared')
    if 'rating2' in records and rater_id(records['rating1']['rater']) == rater_id(records['rating2']['rater']):
        raise ValueError('Two distinct rater identities are required')
    if (study / '.incomplete').exists():
        raise ValueError('Incomplete study write; retain this trial and start a new one')
    return records, previous


def prepare(args):
    manifest_bytes = data(args.manifest)
    manifest = parse_json(manifest_bytes)
    if (set(manifest) != {'study_id', 'scope', 'seed', 'q', 'source_ids', 'runtime_sha256'}
            or not text(manifest['study_id']) or manifest['scope'] != 'known_development'
            or type(manifest['seed']) is not int or not -2147483647 <= manifest['seed'] <= 2147483647
            or type(manifest['q']) is not int or not 0 <= manifest['q'] <= 216
            or not isinstance(manifest['source_ids'], dict) or not manifest['source_ids']
            or not all(text(k) and sha(v) for k, v in manifest['source_ids'].items())
            or not sha(manifest['runtime_sha256'])):
        raise ValueError('Invalid development manifest; heldout qualification is not supported')
    inputs = {key: {'path': str(Path(path).resolve()), 'sha256': hashlib.sha256(manifest_bytes).hexdigest() if key == 'manifest' else digest(path)}
              for key, path in (('manifest', args.manifest), ('snapshot', args.snapshot), ('checkpoint', args.checkpoint))}
    args.study.mkdir(mode=0o700, parents=False, exist_ok=False)
    store(args.study, 'prepared', {'manifest': manifest, 'inputs': inputs}, {}, sync_parent=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'lock', 'rate', 'reveal', 'feedback', 'status'))
    parser.add_argument('study', type=Path)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--snapshot', type=Path)
    parser.add_argument('--checkpoint', type=Path)
    parser.add_argument('--record', type=Path)
    parser.add_argument('--slot', choices=('1', '2'))
    args = parser.parse_args()
    try:
        if not args.study.is_absolute():
            raise ValueError('Use an absolute, new private study directory')
        args.study = args.study.resolve()
        if args.study.is_relative_to(ROOT) or any((parent / '.git').exists() for parent in (args.study, *args.study.parents)):
            raise ValueError('Study data must stay outside every repository checkout')
        if args.action == 'prepare':
            if any(value is None for value in (args.manifest, args.snapshot, args.checkpoint)):
                raise ValueError('Preparation needs manifest, snapshot and checkpoint')
            prepare(args)
        else:
            records, previous = state(args.study)
            if args.action == 'status':
                a, b = records.get('rating1'), records.get('rating2')
                print(json.dumps({'stages': list(records), 'ratings_agree': None if a is None or b is None else
                    all(a[key] == b[key] for key in ('signal', 'channel', 'reversal')),
                    'progression': 'not_assessed', 'economic_correctness': 'not_verified',
                    'heldout_qualification': 'not_verified', 'human_blinding': 'not_verified'}))
                return 0
            stage = {'lock': 'choice', 'rate': 'rating' + (args.slot or ''),
                     'reveal': 'reveal', 'feedback': 'feedback'}[args.action]
            if stage not in STAGES or len(records) >= len(STAGES) or STAGES[len(records)] != stage:
                raise ValueError('Stage already recorded or required predecessor missing')
            if args.record is None:
                raise ValueError('This stage needs --record')
            if stage == 'reveal':
                # Do not read the result before the choice and both ratings exist.
                record = {'path': str(args.record.resolve()), 'sha256': digest(args.record)}
            else:
                record = read_json(args.record)
                if not valid_record(stage, record):
                    raise ValueError('Invalid ' + stage + ' record')
                if stage == 'rating2' and rater_id(record['rater']) == rater_id(records['rating1']['rater']):
                    raise ValueError('Two distinct rater identities are required')
            store(args.study, stage, record, previous)
        print(json.dumps({'recorded': args.action, 'study': str(args.study)}))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('Study unchanged or partial record retained: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
