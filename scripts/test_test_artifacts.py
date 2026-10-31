#!/usr/bin/env python3
"""Exercise expiration and deletion boundaries using temporary directories only."""
import json
import os
from pathlib import Path
import tempfile
import time
import unittest

from test_artifacts import cleanup, initialize, new_run, finish_run


class ArtifactRetentionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'artifacts'
        initialize(self.root)
        self.now = time.time()

    def run_at_age(self, label, days):
        run = new_run(label, self.root)
        (run / 'capture.mp4').write_bytes(b'test recording')
        timestamp = self.now - days * 86400
        marker = run / '.run.json'
        data = json.loads(marker.read_text())
        data['createdAt'] = timestamp
        marker.write_text(json.dumps(data))
        for path in [*run.iterdir(), run]:
            os.utime(path, (timestamp, timestamp))
        return run

    def test_dry_run_then_delete_only_expired_batches(self):
        old = self.run_at_age('old', 30)
        previous = self.run_at_age('previous', 2)
        current = self.run_at_age('current', 0)
        result = cleanup(self.root, now=self.now)
        self.assertEqual(result['expiredRuns'], [str(old)])
        self.assertTrue(old.exists())
        cleanup(self.root, apply=True, now=self.now)
        self.assertFalse(old.exists())
        self.assertTrue(previous.exists())
        self.assertTrue(current.exists())

    def test_keep_latest_two_even_if_both_are_old(self):
        first = self.run_at_age('first', 40)
        second = self.run_at_age('second', 30)
        third = self.run_at_age('third', 20)
        cleanup(self.root, apply=True, now=self.now)
        self.assertFalse(first.exists())
        self.assertTrue(second.exists())
        self.assertTrue(third.exists())

    def test_protect_recent_writes_and_active_or_pinned_runs(self):
        recent_write = self.run_at_age('recent-write', 40)
        os.utime(recent_write / 'capture.mp4', (self.now, self.now))
        pinned = self.run_at_age('pinned', 40)
        (pinned / '.keep').touch()
        active = self.run_at_age('active', 40)
        (active / '.active').touch()
        # Force old mtimes to prove the flags protect runs, independently of age.
        for run, flag in [(pinned, '.keep'), (active, '.active')]:
            for path in [run / flag, run]:
                os.utime(path, (self.now - 40 * 86400,) * 2)
        self.run_at_age('new-one', 1)
        self.run_at_age('new-two', 0)
        cleanup(self.root, apply=True, now=self.now)
        for run in [recent_write, pinned, active]:
            self.assertTrue(run.exists())

    def test_nested_symlinks_never_delete_their_targets(self):
        outside = Path(self.temp.name) / 'outside'
        outside.mkdir()
        (outside / 'source.txt').write_text('must survive')
        old = self.run_at_age('old', 30)
        (old / 'external').symlink_to(outside, target_is_directory=True)
        os.utime(old, (self.now - 30 * 86400,) * 2)
        self.run_at_age('new-one', 1)
        self.run_at_age('new-two', 0)
        cleanup(self.root, apply=True, now=self.now)
        self.assertFalse(old.exists())
        self.assertEqual((outside / 'source.txt').read_text(), 'must survive')

    def test_unknown_directories_and_top_level_symlinks_are_skipped(self):
        unknown = self.root / 'runs' / 'unmanaged'
        unknown.mkdir()
        link = self.root / 'runs' / 'external-link'
        link.symlink_to(unknown, target_is_directory=True)
        result = cleanup(self.root, apply=True, now=self.now)
        self.assertEqual(set(result['skippedUnknownPaths']), {str(unknown), str(link)})
        self.assertTrue(unknown.exists())
        self.assertTrue(link.is_symlink())

    def test_refuse_unmarked_root_and_symlinked_runs(self):
        with self.assertRaises(FileNotFoundError):
            cleanup(Path(self.temp.name), apply=True)
        (self.root / 'runs').rmdir()
        (self.root / 'runs').symlink_to(self.temp.name, target_is_directory=True)
        with self.assertRaises(ValueError):
            cleanup(self.root, apply=True)

    def test_refuse_adopting_nonempty_directory(self):
        root = Path(self.temp.name) / 'other-project'
        root.mkdir()
        (root / 'source.txt').write_text('keep')
        with self.assertRaises(ValueError):
            initialize(root)

    def test_invalid_retention_or_label_is_rejected(self):
        with self.assertRaises(ValueError):
            cleanup(self.root, days=0)
        with self.assertRaises(ValueError):
            cleanup(self.root, keep=1)
        with self.assertRaises(ValueError):
            new_run('../escape', self.root)

    def test_finish_removes_active_and_pins_failed_evidence(self):
        run = new_run('failed-capture', self.root, active=True)
        self.assertTrue((run / '.active').exists())
        finish_run(run, failed=True, root=self.root)
        self.assertFalse((run / '.active').exists())
        self.assertTrue((run / '.keep').exists())

    def test_finish_rejects_unmanaged_path(self):
        outside = Path(self.temp.name) / 'unmanaged'
        outside.mkdir()
        (outside / '.active').touch()
        with self.assertRaises(ValueError):
            finish_run(outside, root=self.root)
        self.assertTrue((outside / '.active').exists())

    def test_root_marker_symlink_is_rejected(self):
        marker = next(self.root.glob('.*-test-artifacts.json'))
        contents = marker.read_text()
        outside = Path(self.temp.name) / 'marker.json'
        outside.write_text(contents)
        marker.unlink()
        marker.symlink_to(outside)
        with self.assertRaises(ValueError):
            cleanup(self.root, apply=True)


if __name__ == '__main__':
    unittest.main()
