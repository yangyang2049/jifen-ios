"""Verify that capture evidence identifies the selected XCTest products."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch, Mock

import capture_duo_layout as capture


class CaptureProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='jifen-capture-provenance-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / 'build/duo').mkdir(parents=True)
        self.app = self.root / 'Selected Products' / 'jifen.app'
        self.host = self.root / 'Selected Products' / 'Runner.app'
        self.bundle = self.host / 'PlugIns' / 'jifenUITests.xctest'
        for bundle, executable in [(self.app, 'jifen'), (self.host, 'Runner'), (self.bundle, 'jifenUITests')]:
            bundle.mkdir(parents=True, exist_ok=True)
            (bundle / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': executable}))
            (bundle / executable).write_bytes(('selected-build-' + executable).encode())
        self.dylib = self.app / 'jifen.debug.dylib'
        self.dylib.write_bytes(b'selected-build-debug-code')
        self.configuration = self.root / 'selected.xctestrun'
        self.target = {
            'BlueprintName': 'jifenUITests',
            'UITargetAppPath': '__TESTROOT__/Selected Products/jifen.app',
            'TestHostPath': '__TESTROOT__/Selected Products/Runner.app',
            'TestBundlePath': '__TESTHOST__/PlugIns/jifenUITests.xctest',
        }
        self.configuration.write_bytes(plistlib.dumps({'jifenUITests': self.target}))

    def run_capture(self, *, name='checkpoint', window_size=(100, 200), live=False,
                    inventory=None, display_pixels=None):
        container = self.root / 'Containers' / 'runner'
        marker = container / 'tmp' / 'duo-capture.json'
        marker.parent.mkdir(parents=True)
        process = Mock()
        process.poll.side_effect = [None, 0, 0]
        process.wait.return_value = 0
        self.screenshot_commands = []

        def launch(*args, **kwargs):
            marker.write_text(json.dumps({'width': window_size[0], 'height': window_size[1], 'name': name}))
            return process

        def screenshot(command, **kwargs):
            self.screenshot_commands.append(command)
            selected = next(argument.split('=', 1)[1] for argument in command if argument.startswith('--display='))
            pixels = (display_pixels or {'ABC-123': (100, 200)})[selected]
            Path(command[-1]).write_bytes(b'\0' * 16 + struct.pack('>II', *pixels))

        inventory = inventory or 'Port:\n    Display class: 0\nUUID: ABC-123\nDefault width: 100\nDefault height: 200'
        arguments = ['capture_duo_layout.py', 'test-device', 'folded', '--chapter', 'home',
                     '--xctestrun', str(self.configuration), '--output-root', str(self.root / 'output')]
        if live:
            arguments.append('--live')
        with patch('sys.argv', arguments), patch.object(capture, '__file__', str(self.root / 'scripts/capture_duo_layout.py')), \
                patch.object(capture.os, 'chdir'), patch.object(capture, 'output', side_effect=[inventory, str(container)]), \
                patch.object(capture.subprocess, 'Popen', side_effect=launch) as popen, \
                patch.object(capture.subprocess, 'run', side_effect=screenshot), \
                patch.object(capture.time, 'sleep'):
            self.assertEqual(capture.main(), 0)
        return json.loads((self.root / 'output/folded/home/session.json').read_text()), popen.call_args.args[0]

    def duo_inventory(self):
        return '\n'.join([
            'Port:', '    Display class: 0', 'UUID: A0-A0', 'Default width: 1398', 'Default height: 2034',
            'Port:', '    Display class: 0', 'UUID: B0-B0', 'Default width: 2007', 'Default height: 2853',
        ])

    def test_live_open_uses_inner_display_when_ax_retains_outer_window_size(self):
        manifest, _ = self.run_capture(
            name='duo_341_multi341_draft_open', window_size=(466, 678), live=True,
            inventory=self.duo_inventory(), display_pixels={'A0-A0': (1398, 2034), 'B0-B0': (2007, 2853)}
        )
        self.assertEqual(len(self.screenshot_commands), 1)
        self.assertIn('--display=B0-B0', self.screenshot_commands[0])
        evidence = manifest['captures'][0]
        self.assertEqual(evidence['explicit_pose'], 'open')
        self.assertEqual(evidence['display_selection'], 'explicit-live-pose')
        self.assertEqual(evidence['display'], 'B0-B0')
        self.assertEqual(evidence['pixels'], [2007, 2853])
        self.assertEqual((evidence['width'], evidence['height']), (466, 678))
        self.assertTrue(evidence['ax_display_aspect_mismatch'])
        self.assertAlmostEqual(evidence['ax_window_aspect'], 678 / 466)
        self.assertAlmostEqual(evidence['display_aspect'], 2853 / 2007)

    def test_live_closed_before_uses_outer_display_and_reports_stale_inner_ax_size(self):
        manifest, _ = self.run_capture(
            name='duo_341_multi_draft_closed_before', window_size=(669, 951), live=True,
            inventory=self.duo_inventory(), display_pixels={'A0-A0': (1398, 2034), 'B0-B0': (2007, 2853)}
        )
        self.assertEqual(len(self.screenshot_commands), 1)
        self.assertIn('--display=A0-A0', self.screenshot_commands[0])
        evidence = manifest['captures'][0]
        self.assertEqual(evidence['explicit_pose'], 'closed')
        self.assertEqual(evidence['display_selection'], 'explicit-live-pose')
        self.assertEqual(evidence['display'], 'A0-A0')
        self.assertEqual(evidence['pixels'], [1398, 2034])
        self.assertEqual((evidence['width'], evidence['height']), (669, 951))
        self.assertTrue(evidence['ax_display_aspect_mismatch'])
        self.assertAlmostEqual(evidence['ax_window_aspect'], 951 / 669)
        self.assertAlmostEqual(evidence['display_aspect'], 2034 / 1398)

    def test_custom_xctestrun_hashes_the_executed_app_host_and_test_bundle(self):
        manifest, command = self.run_capture()
        self.assertEqual(command[command.index('-xctestrun') + 1], str(self.configuration))
        expected = [self.app / 'jifen', self.host / 'Runner', self.bundle / 'jifenUITests', self.dylib]
        self.assertEqual(manifest['binary_sha256'], {
            str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in expected
        })
        self.assertEqual(manifest['xctestrun'], str(self.configuration))
        self.assertEqual(manifest['xctestrun_sha256'], hashlib.sha256(self.configuration.read_bytes()).hexdigest())

    def test_version_two_ignores_disabled_configurations(self):
        disabled = {**self.target, 'UITargetAppPath': '/missing/disabled.app'}
        self.configuration.write_bytes(plistlib.dumps({'TestConfigurations': [
            {'Name': 'Disabled', 'IsEnabled': False, 'TestTargets': [disabled]},
            {'Name': 'Enabled', 'TestTargets': [self.target]},
        ]}))
        manifest, _ = self.run_capture()
        self.assertIn(str(self.dylib), manifest['binary_sha256'])

    def test_missing_selected_binary_fails_before_contacting_the_simulator(self):
        (self.bundle / 'jifenUITests').unlink()
        arguments = ['capture_duo_layout.py', 'test-device', 'folded', '--xctestrun', str(self.configuration)]
        with patch('sys.argv', arguments), patch.object(capture, 'output') as output:
            with self.assertRaises(FileNotFoundError):
                capture.main()
            output.assert_not_called()


if __name__ == '__main__':
    unittest.main()
