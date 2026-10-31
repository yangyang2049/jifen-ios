"""Exercise real Bash EXIT traps against temporary managed roots, without a simulator."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ShellArtifactTests(unittest.TestCase):
    def run_session(self, status):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            scripts = folder / 'scripts'
            scripts.mkdir()
            source = Path(__file__).parent
            text = (source / 'test_artifacts.py').read_text()
            text = text.replace("ROOT = Path.home() / 'Library/Developer/jifen-ios-test-artifacts'",
                                'ROOT = Path(' + repr(str(folder / 'artifacts')) + ')')
            (scripts / 'test_artifacts.py').write_text(text)
            shutil.copy2(source / 'test_artifacts.sh', scripts)
            command = 'set -euo pipefail\nsource "$1/test_artifacts.sh"\nstart_test_artifacts shell-test\nexit "$2"'
            result = subprocess.run(['/bin/bash', '-c', command, 'test', str(scripts), str(status)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, status, result.stderr)
            runs = list((folder / 'artifacts/runs').iterdir())
            self.assertEqual(len(runs), 1)
            self.assertFalse((runs[0] / '.active').exists())
            self.assertEqual((runs[0] / '.keep').exists(), status != 0)

    def test_successful_capture_finishes_automatically(self):
        self.run_session(0)

    def test_failed_capture_keeps_evidence_and_exit_code(self):
        self.run_session(3)


if __name__ == '__main__':
    unittest.main()
