"""Check current tracked UTF-8 text for private creator-name fragments.

No extension allowlist or size limit: every `git ls-files` working-tree file is
read. NUL-containing or non-UTF-8 files are excluded and reported. This does not
audit history, Git metadata, filenames, untracked files, binary/embedded metadata,
external links' contents, or other aliases/obfuscated spellings.
"""
from collections import Counter
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
# Split fragments keep the scanner's own source free of private-name matches.
PRIVATE_NAME = re.compile("ja" + "red|bl" + "and", re.IGNORECASE)


class PublicAttributionTests(unittest.TestCase):
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
