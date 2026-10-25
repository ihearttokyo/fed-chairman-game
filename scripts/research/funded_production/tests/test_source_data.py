"""Canonical historical input custody, independent of the evolving game tree."""
import hashlib
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from scripts.research.funded_production import source_data


class FrozenSourceTests(unittest.TestCase):
    def test_exact_existing_pins_and_origin(self):
        expected = {
            'parameters.json': '6e45d72e2231d59f67305270c10ccb5b7afcfc2a3475ec8eb72a497522320949',
            'economy.gd': '52580ad1073aca877912527ecc7a6aa36f935de17fbc93e460323b8eba4a0987',
            'portfolio_reference.json': '5e7362e82bc848e85869df0c69334f05eb68349b19bf84f7bd7d03b283b19e7e',
        }
        self.assertEqual(dict(source_data.SOURCE_DIGESTS), expected)
        self.assertEqual(source_data.SOURCE_ORIGIN_COMMIT,
                         '2703f7965a3c5f67c5bc233ce3d3c6560268ce7c')
        self.assertEqual(source_data.MODEL_DIR,
                         Path(source_data.__file__).resolve().parent / 'reference_inputs')
        for name, digest in expected.items():
            with self.subTest(name=name):
                self.assertEqual(hashlib.sha256((source_data.MODEL_DIR / name).read_bytes()).hexdigest(), digest)
        source_data.check_sources()

    def test_every_reader_refuses_each_changed_frozen_input(self):
        with tempfile.TemporaryDirectory(prefix='fed-frozen-inputs-') as directory:
            target = Path(directory)
            for name in source_data.SOURCE_DIGESTS:
                shutil.copyfile(source_data.MODEL_DIR / name, target / name)
            for name in source_data.SOURCE_DIGESTS:
                original = (target / name).read_bytes()
                (target / name).write_bytes(original + b'\n')
                with patch.object(source_data, 'MODEL_DIR', target):
                    for reader in (source_data.check_sources, source_data.load_parameters,
                                   source_data.load_portfolio):
                        with self.subTest(name=name, reader=reader.__name__):
                            with self.assertRaisesRegex(ValueError, 'Reference input changed: ' + name):
                                reader()
                (target / name).write_bytes(original)

    def test_missing_frozen_input_refuses_without_fallback(self):
        with tempfile.TemporaryDirectory(prefix='fed-missing-input-') as directory:
            target = Path(directory)
            for name in ('parameters.json', 'portfolio_reference.json'):
                shutil.copyfile(source_data.MODEL_DIR / name, target / name)
            with patch.object(source_data, 'MODEL_DIR', target):
                with self.assertRaises(FileNotFoundError):
                    source_data.check_sources()


if __name__ == '__main__':
    unittest.main()
