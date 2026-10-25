"""A copied qualification fixture must not need the owner's private task tree."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from scripts.research.funded_production import source_data


class PortabilityTests(unittest.TestCase):
    def test_cold_copy_roundtrip_replay_and_source_drift(self):
        package = Path(source_data.__file__).parent
        with tempfile.TemporaryDirectory(prefix='fed-reference-') as directory:
            root = Path(directory)
            target = root / 'scripts/research/funded_production'
            target.parent.mkdir(parents=True)
            shutil.copytree(package, target, ignore=shutil.ignore_patterns('__pycache__'))
            frozen_inputs = target / 'reference_inputs'
            self.assertFalse((root / 'game').exists())
            env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
            env.pop('PYTHONPATH', None)
            command = '''
from fractions import Fraction as F
from scripts.research.funded_production import checkpoint as k, choice
s = k.initial(growth=0)
z = k.adopt(s, k.m.Policy(3.5,3.5), additional_units=F(1,4))
assert z.ok, z.reason
assert k.decode_checkpoint(k.encode_checkpoint(z.state)) == z.state
assert k.replay(s, k.decode_event(k.encode_event(z.event))).state == z.state
assert choice.__file__.startswith(str(__import__('pathlib').Path.cwd()))
print('portable roundtrip/replay passed')
'''
            completed = subprocess.run([sys.executable, '-B', '-c', command], cwd=root,
                                       env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn('portable roundtrip/replay passed', completed.stdout)
            # A changing shipping model must neither supply nor refresh the
            # historical qualification inputs, even when both trees exist.
            model = root / 'game/model'
            model.mkdir(parents=True)
            originals = {name: (frozen_inputs / name).read_bytes()
                         for name in source_data.SOURCE_DIGESTS}
            for name, content in originals.items():
                (model / name).write_bytes(content + b'\n')
            independent = subprocess.run([sys.executable, '-B', '-c', command], cwd=root,
                                         env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(independent.returncode, 0, independent.stderr)
            for name, content in originals.items():
                self.assertEqual((frozen_inputs / name).read_bytes(), content)
                with self.subTest(changed_frozen_input=name):
                    (frozen_inputs / name).write_bytes(content + b'\n')
                    rejected = subprocess.run([sys.executable, '-B', '-c', command], cwd=root,
                                              env=env, capture_output=True, text=True, timeout=30)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertIn('Reference input changed: ' + name, rejected.stderr)
                    (frozen_inputs / name).write_bytes(content)


if __name__ == '__main__':
    unittest.main()
