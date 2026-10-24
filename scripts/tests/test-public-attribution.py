"""Check current tracked UTF-8 text for private creator-name fragments.

No extension allowlist or size limit: every `git ls-files` working-tree file is
read. The UTF-8 check excludes and reports NUL-containing or non-UTF-8 files.
It does not audit history, Git metadata, filenames, untracked files, other binary metadata,
external links' contents, or other aliases/obfuscated spellings.
Additional checks scan raw tracked binary bytes and decoded Blender source;
these literal checks do not establish full binary or metadata anonymity.
"""
from collections import Counter
from pathlib import Path
from types import SimpleNamespace
import ast
import re
import subprocess
import unittest

try:
    from compression import zstd
except ImportError:
    zstd = None


ROOT = Path(__file__).resolve().parents[2]
# Split fragments keep the scanner's own source free of private-name matches.
PRIVATE_NAME = re.compile("ja" + "red|bl" + "and", re.IGNORECASE)
PRIVATE_BYTES = re.compile(PRIVATE_NAME.pattern.encode(), re.IGNORECASE)
HOME_PATH = re.compile(rb"/(?:Us" + rb"ers|ho" + rb"me)/[^/\x00\r\n]+", re.IGNORECASE)
DECODE_LIMIT = 100 * 1024 * 1024


class PublicAttributionTests(unittest.TestCase):
    def test_builder_clears_fixed_directory_buffer_tails_via_public_setter(self):
        source = ast.parse((ROOT / "game/art/build_city.py").read_text())
        helper = next(node for node in source.body if isinstance(node, ast.FunctionDef)
                      and node.name == "sanitize_file_browser_directories")

        class CachedDirectory:
            def __init__(self, capacity):
                self.buffer = bytearray(b"x" * capacity)
                self.bl_rna = SimpleNamespace(properties={
                    "directory": SimpleNamespace(length_max=capacity)
                })

            @property
            def directory(self):
                return bytes(self.buffer).split(b"\0", 1)[0]

            @directory.setter
            def directory(self, value):
                capacity = len(self.buffer)
                value = value[:capacity - 1]
                self.buffer[:len(value) + 1] = value + b"\0"

        params = CachedDirectory(1090)
        # A shorter assignment alone leaves this old cached path after its NUL.
        params.directory = b"/Us" + b"ers/" + b"old-folder/" * 4 + b"ja" + b"red/"
        params.directory = b"/private/tmp/"
        self.assertIsNotNone(PRIVATE_BYTES.search(params.buffer))
        browser = SimpleNamespace(type="FILE_BROWSER", params=params)
        screens = [SimpleNamespace(areas=[SimpleNamespace(spaces=[
            SimpleNamespace(type="VIEW_3D"), browser,
            SimpleNamespace(type="FILE_BROWSER", params=None)
        ])])]
        namespace = {"bpy": SimpleNamespace(data=SimpleNamespace(screens=screens))}
        exec(compile(ast.Module(body=[helper], type_ignores=[]), "<builder-helper>", "exec"), namespace)
        namespace[helper.name]()
        self.assertEqual(params.directory, b"/private/tmp/")
        self.assertIsNone(PRIVATE_BYTES.search(params.buffer))
        self.assertIsNone(HOME_PATH.search(params.buffer))
        params.bl_rna.properties["directory"].length_max = 0
        with self.assertRaisesRegex(RuntimeError, "capacity"):
            namespace[helper.name]()

    def test_raw_tracked_binary_has_no_literal_private_name(self):
        tracked = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=ROOT
        ).decode("utf-8").split("\0")[:-1]
        binaries = []
        for name in tracked:
            data = (ROOT / name).read_bytes()
            try:
                data.decode("utf-8")
                binary = b"\0" in data
            except UnicodeDecodeError:
                binary = True
            if binary:
                binaries.append(name)
                self.assertIsNone(PRIVATE_BYTES.search(data), name)
                self.assertIsNone(HOME_PATH.search(data), name)
        self.assertTrue(binaries, "No binary files found; scan would be vacuous")
        print(f"Raw binary literal scan: {len(binaries)} tracked files", flush=True)

    @unittest.skipIf(zstd is None, "Decoded Blender check requires Python 3.14 compression.zstd")
    def test_decoded_blender_has_no_private_name_or_home_path(self):
        source = ROOT / "game/art/policy_city.blend"
        # Blender supports uncompressed files too; no external decoder or bpy.
        with source.open("rb") as stream:
            plain = stream.read(7) == b"BLENDER"
        opener = source.open if plain else lambda mode: zstd.open(source, mode)
        total = 0
        decoded = bytearray()
        with opener("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                total += len(chunk)
                self.assertLessEqual(total, DECODE_LIMIT, "Blender decode exceeds 100 MiB limit")
                decoded.extend(chunk)
        self.assertTrue(decoded.startswith(b"BLENDER"), "Not a decoded Blender file")
        for label, pattern in (("creator name", PRIVATE_BYTES), ("home path", HOME_PATH)):
            match = pattern.search(decoded)
            self.assertIsNone(match, f"Decoded Blender {label} at offset {match.start() if match else 'none'}")
        print(f"Decoded Blender literal scan: {total} bytes (limit {DECODE_LIMIT})", flush=True)

    def test_current_tracked_text_has_no_private_creator_name(self):
        tracked = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=ROOT
        ).decode("utf-8").split("\0")[:-1]
        self.assertTrue(tracked, "No tracked files found; scan would be vacuous")
        covered = Counter()
        skipped = []
        matches = []
        for name in tracked:
            data = (ROOT / name).read_bytes()
            if b"\0" in data:
                skipped.append(name)
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                skipped.append(name)
                continue
            covered[Path(name).suffix or "<no suffix>"] += 1
            matches.extend(
                f"{name}:{number}"
                for number, line in enumerate(text.splitlines(), 1)
                if PRIVATE_NAME.search(line)
            )
        self.assertTrue(covered, "No UTF-8 text files found")
        print("Covered tracked UTF-8 text: " + ", ".join(
            f"{suffix}={count}" for suffix, count in sorted(covered.items())
        ), flush=True)
        print("Excluded binary/non-UTF-8 files: " + ", ".join(skipped), flush=True)
        self.assertEqual(matches, [], "Private creator-name matches:\n" + "\n".join(matches))


if __name__ == "__main__":
    unittest.main(verbosity=2)
