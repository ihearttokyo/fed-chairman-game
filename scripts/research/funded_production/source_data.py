"""Shared repository inputs for an offline qualification candidate, not a game backend."""
from pathlib import Path
from types import MappingProxyType
import hashlib
import json

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = REPOSITORY_ROOT / 'game' / 'model'
SOURCE_PARAMETERS_SHA256 = '6e45d72e2231d59f67305270c10ccb5b7afcfc2a3475ec8eb72a497522320949'
SOURCE_CORE_SHA256 = '312b25f1cf679b027ae96766c9bdbf9d93f619469afdcb37388d27ad953c4c9c'
SOURCE_PORTFOLIO_SHA256 = '5e7362e82bc848e85869df0c69334f05eb68349b19bf84f7bd7d03b283b19e7e'
SOURCE_DIGESTS = MappingProxyType({
    'parameters.json': SOURCE_PARAMETERS_SHA256,
    'economy.gd': SOURCE_CORE_SHA256,
    'portfolio_reference.json': SOURCE_PORTFOLIO_SHA256,
})


def _verified_bytes(name):
    content = (MODEL_DIR / name).read_bytes()
    if hashlib.sha256(content).hexdigest() != SOURCE_DIGESTS[name]:
        raise ValueError('Reference input changed: ' + name)
    return content


def check_sources():
    for name in SOURCE_DIGESTS:
        _verified_bytes(name)


def load_parameters():
    check_sources()
    return MappingProxyType({row['key']: row['value']
                             for row in json.loads(_verified_bytes('parameters.json'))})


def load_portfolio():
    check_sources()
    return json.loads(_verified_bytes('portfolio_reference.json'))
