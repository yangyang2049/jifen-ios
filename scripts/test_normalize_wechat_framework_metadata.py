import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import normalize_wechat_framework_metadata as metadata


class WeChatFrameworkMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.framework = Path(self.temp.name) / "WechatOpenSDK.framework"
        self.framework.mkdir()
        self.plist = self.framework / "Info.plist"
        self.original = {
            "CFBundleIdentifier": "com.tencent.WechatOpenSDK",
            "CFBundleExecutable": "WechatOpenSDK",
            "MinimumOSVersion": "12.0",
            "CFBundleVersion": "1.0.0",
        }
        self.plist.write_bytes(plistlib.dumps(self.original))
        (self.framework / "WechatOpenSDK").write_bytes(b"fixture binary")

    def command(self, stdout):
        return patch.object(metadata.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout))

    def test_check_rejects_the_reported_mismatch_without_modifying_the_bundle(self):
        before = self.plist.read_bytes()
        with self.command(" platform IOS\n minos 26.0\n sdk 27.1\n"):
            with self.assertRaisesRegex(ValueError, "plist 12.0, Mach-O requires 26.0"):
                metadata.normalize(self.framework, check_only=True)
        self.assertEqual(self.plist.read_bytes(), before)

    def test_uses_the_highest_binary_minimum_and_preserves_other_fields(self):
        with self.command(" minos 26.0\n minos 26.1\n"), patch.dict(os.environ, {"CODE_SIGNING_ALLOWED": "NO"}):
            self.assertTrue(metadata.normalize(self.framework))
            after = plistlib.loads(self.plist.read_bytes())
            self.assertEqual(after, dict(self.original, MinimumOSVersion="26.1"))
            before = self.plist.read_bytes()
            self.assertFalse(metadata.normalize(self.framework))
            self.assertEqual(self.plist.read_bytes(), before)

    def test_signed_build_requires_an_identity_before_changing_the_plist(self):
        before = self.plist.read_bytes()
        with self.command(" minos 26.0\n"), patch.dict(os.environ, {
            "CODE_SIGNING_ALLOWED": "YES", "EXPANDED_CODE_SIGN_IDENTITY": ""
        }):
            with self.assertRaisesRegex(ValueError, "signing identity"):
                metadata.normalize(self.framework)
        self.assertEqual(self.plist.read_bytes(), before)

    def test_changed_signed_bundle_is_resigned_and_verified(self):
        with self.command(" minos 26.0\n") as run, patch.dict(os.environ, {
            "CODE_SIGNING_ALLOWED": "YES", "EXPANDED_CODE_SIGN_IDENTITY": "-"
        }):
            metadata.normalize(self.framework)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual([command[1] for command in commands if command[0] == "/usr/bin/codesign"],
                         ["--force", "--verify"])

    def test_unreadable_binary_metadata_fails_instead_of_guessing_from_the_app(self):
        with self.command("not a Mach-O executable"):
            with self.assertRaisesRegex(ValueError, "No Mach-O minimum"):
                metadata.normalize(self.framework)

    def test_unexpected_framework_identity_is_rejected(self):
        self.original["CFBundleIdentifier"] = "unrelated.framework"
        self.plist.write_bytes(plistlib.dumps(self.original))
        with self.assertRaisesRegex(ValueError, "identity"):
            metadata.normalize(self.framework)


if __name__ == "__main__":
    unittest.main()
