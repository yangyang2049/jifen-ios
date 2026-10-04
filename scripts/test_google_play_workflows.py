"""Offline regressions for Play commit checks and screenshot resource aliases."""
import contextlib
import copy
import html
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch
from PIL import Image


WORKFLOW = Path(__file__).resolve().parents[1] / "marketing/google-play/localization-2026-10-02"


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, WORKFLOW / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


api = load_module("offline_play_api", "play_api.py")
with patch.dict(sys.modules, {"play_api": api}):
    uploader = load_module("offline_upload_localized_ui", "upload_localized_ui.py")
evidence = load_module("offline_capture_evidence", "capture_evidence.py")
with patch.dict(sys.modules, {"capture_evidence": evidence, "play_api": api}):
    capture = load_module("offline_capture_localized_gp", "capture_localized_gp.py")
    compositor = load_module("offline_composite_localized_bg", "composite_localized_bg.py")
    verifier = load_module("offline_verify_localized_ui", "verify_localized_ui.py")
    chinese_verifier = load_module("offline_verify_zh_cn", "verify_zh_cn.py")


class FakePlayClient:
    def __init__(self, expected, corrupt=None):
        self.expected = expected
        self.corrupt = corrupt
        self.calls = []
        self.lock = threading.Lock()

    def call(self, method, path, body=None, image=None):
        with self.lock:
            self.calls.append((method, path))
        if method == "POST" and path.endswith("/edits"):
            return {"id": "inspection"}
        if method != "GET" or "/listings/" not in path:
            return {}
        language = path.split("/listings/", 1)[1].split("/", 1)[0]
        expected = self.expected[language]
        if path.endswith("/phoneScreenshots"):
            hashes = list(expected["hashes"])
            if "/staged/" in path and language == "zh-CN":
                if self.corrupt == "hash":
                    hashes[2] = "unexpected-hash"
                elif self.corrupt == "order":
                    hashes[0], hashes[1] = hashes[1], hashes[0]
                elif self.corrupt == "count":
                    hashes.pop()
            return {"images": [{"sha256": value} for value in hashes]}
        listing = copy.deepcopy(expected["listing"])
        if "/staged/" in path and language == "zh-CN" and self.corrupt == "listing":
            listing["title"] = "Unexpected title"
        return listing


class GooglePlayCommitTests(unittest.TestCase):
    def fixture(self, corrupt=None):
        expected = {
            language: {
                "listing": {
                    "language": language,
                    "title": "Title " + language,
                    "shortDescription": "Short description",
                    "fullDescription": "Full description",
                },
                "hashes": [language + "-" + str(number) for number in range(7)],
            }
            for language in ("en-US", "zh-CN")
        }
        state = {
            "editId": "staged", "committed": False, "validated": True,
            "expected": expected, "createdListingLocales": [], "fullReplaceLocales": ["zh-CN"],
        }
        plan = [
            {"language": language, "listing": value["listing"],
             "images": [{"sha256": sha} for sha in value["hashes"]]}
            for language, value in expected.items()
        ]
        return state, plan, FakePlayClient(expected, corrupt)

    def run_commit(self, state, plan, client):
        def read(path):
            if path.name == "localized-ui-api-state.json":
                return state
            if path.name == "localized-ui-verification.json":
                return {}
            raise AssertionError("Unexpected file read: " + str(path))

        with patch.object(api, "read", side_effect=read), \
             patch.object(api, "dump"), \
             patch.object(api, "local_plan", return_value=("offline.test.package", plan)), \
             patch.object(api, "token", return_value="offline-token"), \
             patch.object(uploader, "ReliableClient", return_value=client), \
             patch.object(sys, "argv", ["upload_localized_ui.py", "--credentials", "unused.json", "--commit"]), \
             contextlib.redirect_stdout(io.StringIO()):
            uploader.main()

    def testEveryExpectedLocaleIsReadBackBeforeCommit(self):
        state, plan, client = self.fixture()
        self.run_commit(state, plan, client)
        commit_index = next(i for i, call in enumerate(client.calls) if call[1].endswith(":commit"))
        before_commit = client.calls[:commit_index]
        base = "/applications/offline.test.package/edits/staged"
        for language in state["expected"]:
            self.assertIn(("GET", base + "/listings/" + language), before_commit)
            self.assertIn(("GET", base + "/listings/" + language + "/phoneScreenshots"), before_commit)
        self.assertTrue(state["committed"])
        self.assertTrue(state["postCommitReadbackVerified"])

    def testRemoteListingImageHashOrderAndCountMismatchPreventCommit(self):
        for corrupt in ("listing", "hash", "order", "count"):
            with self.subTest(corrupt=corrupt):
                state, plan, client = self.fixture(corrupt)
                with self.assertRaisesRegex(ValueError, "Pre-commit readback mismatch: zh-CN"):
                    self.run_commit(state, plan, client)
                self.assertFalse(any(path.endswith(":commit") for _, path in client.calls))
                self.assertFalse(state["committed"])


class GooglePlayCaptureResourceTests(unittest.TestCase):
    def testFinalFormatGateRejectsIncompatibleSpecialOverrides(self):
        default = {
            "tab_score": "Score", "tab_records": "Records", "tab_badminton": "Badminton",
            "cancel": "Cancel", "record_detail_score_trend": "Score trend",
            "record_format_best_of_games": "Best of %1$d", "record_format_points_per_game": "Target %1$d",
            "record_wins": "%1$s wins", "record_detail_game_title": "Game %1$s", "record_detail_set_title": "Set %1$s",
        }
        source = dict(default, pingpong_set_option_best_of_3="Best of 3", record_format_points_per_set="%1$d / %2$d points", winner_wins="%@ wins")
        port = types.ModuleType("port_ios_locales")
        port.load_ios = lambda path: default if path.parent.name == "en.lproj" else source
        port.ios_unescape = lambda value: value
        port.convert_format = lambda value, key: value
        port.format_signature = lambda value: tuple(re.findall(r"%\d*\$?[ds]", value))
        port.android_escape = html.escape
        with patch.dict(sys.modules, {"port_ios_locales": port}), patch.object(sys, "path", list(sys.path)):
            resources = load_module("offline_prepare_special_formats", "prepare_capture_resources.py")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            res = root / "res"
            (res / "values").mkdir(parents=True)
            (res / "values/strings.xml").write_text("<resources>" + "".join(f'<string name="{key}">{value}</string>' for key, value in default.items()) + "</resources>")
            # Hindi has explicit round overrides, in addition to the best-of,
            # points, and winner overrides used for every non-English locale.
            (root / "copy.json").write_text(json.dumps({"localizations": [{"locale": "hi-IN"}]}))
            with patch.object(resources, "ROOT", root), patch.object(resources, "RES", res), \
                 patch.object(resources, "IOS", root / "ios"), patch.object(resources, "REVIEWED", root / "reviewed"), \
                 contextlib.redirect_stdout(io.StringIO()):
                resources.main()
            result = resources.xml_values(res / "values-hi-rIN/gp_capture_strings.xml")
            for key in ("record_format_best_of_games", "record_format_points_per_game", "record_wins", "record_detail_game_title", "record_detail_set_title"):
                self.assertNotIn(key, result, "Special override must preserve the default format contract: " + key)
            self.assertEqual(resources.xml_values(res / "values/strings.xml"), default)
            self.assertEqual(result["cancel"], default["cancel"])

    def testIncompatibleReviewedFormatsNeverReenterThroughMappedKeys(self):
        default = {
            "tab_score": "Score", "tab_records": "Records", "tab_badminton": "Badminton",
            "cancel": "Cancel", "record_detail_score_trend": "Score trend",
            "mapped": "%1$d points", "compatible": "%1$d games", "unmapped": "%1$d rounds",
            "fallback": "%1$d sets", "both_bad": "%1$s player", "record_format_points_per_game": "%1$d points",
        }
        english = {key: value for key, value in default.items() if key != "unmapped"}
        source = dict(english, mapped="%1$d 分", compatible="%1$d 局", fallback="%1$d 盘", both_bad="%1$d 人",
                      pingpong_set_option_best_of_3="三局两胜", record_format_points_per_set="%1$d 分", winner_wins="%@ 获胜")
        reviewed = {"mapped": "%1$d / %2$d 分", "compatible": "%1$d 比赛", "unmapped": "%1$s 轮",
                    "fallback": "%1$s 盘", "both_bad": "%1$s / %2$s 人", "record_format_points_per_game": "%1$d / %2$d 分"}
        port = types.ModuleType("port_ios_locales")
        port.load_ios = lambda path: english if path.parent.name == "en.lproj" else source
        port.ios_unescape = lambda value: value
        port.convert_format = lambda value, key: value
        port.format_signature = lambda value: tuple(re.findall(r"%\d*\$?[ds]", value))
        port.android_escape = html.escape
        with patch.dict(sys.modules, {"port_ios_locales": port}), patch.object(sys, "path", list(sys.path)):
            resources = load_module("offline_prepare_formats", "prepare_capture_resources.py")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            res = root / "res"
            (res / "values").mkdir(parents=True)
            reviewed_dir = root / "reviewed/values-zh"
            reviewed_dir.mkdir(parents=True)
            for path, values in ((res / "values/strings.xml", default), (reviewed_dir / "strings.xml", reviewed)):
                path.write_text("<resources>" + "".join(f'<string name="{key}">{html.escape(value)}</string>' for key, value in values.items()) + "</resources>")
            (root / "copy.json").write_text(json.dumps({"localizations": [{"locale": "zh-CN"}]}))
            with patch.object(resources, "ROOT", root), patch.object(resources, "RES", res), \
                 patch.object(resources, "IOS", root / "ios"), patch.object(resources, "REVIEWED", root / "reviewed"), \
                 contextlib.redirect_stdout(io.StringIO()):
                resources.main()
            result = resources.xml_values(res / "values-zh-rCN/gp_capture_strings.xml")
            self.assertEqual(result["mapped"], source["mapped"])
            self.assertEqual(result["compatible"], reviewed["compatible"])
            self.assertEqual(result["fallback"], source["fallback"])
            self.assertEqual(result["record_format_points_per_game"], source["record_format_points_per_set"])
            self.assertNotIn("unmapped", result)
            self.assertNotIn("both_bad", result)

    def testSimplifiedChineseUsesHansSourceAndChineseResourceQualifier(self):
        reads = []
        default = {
            "tab_score": "Score", "tab_records": "Records", "tab_badminton": "Badminton",
            "cancel": "Cancel", "record_detail_score_trend": "Score trend",
        }
        chinese = {
            "tab_score": "计分", "tab_records": "记录", "game_badminton": "羽毛球",
            "cancel": "取消", "score_trend": "比分走势",
            "pingpong_set_option_best_of_3": "三局两胜",
            "record_format_points_per_set": "每局 %d 分", "winner_wins": "%@ 获胜",
        }

        def load_ios(path):
            reads.append(path.parent.name)
            if path.parent.name == "en.lproj":
                return default
            if path.parent.name == "zh-Hans.lproj":
                return chinese
            raise AssertionError("Unexpected locale source: " + str(path))

        port = types.ModuleType("port_ios_locales")
        port.load_ios = load_ios
        port.ios_unescape = lambda value: value
        port.convert_format = lambda value, key: value
        port.format_signature = lambda value: ()
        port.android_escape = html.escape
        with patch.dict(sys.modules, {"port_ios_locales": port}), patch.object(sys, "path", list(sys.path)):
            resources = load_module("offline_prepare_capture_resources", "prepare_capture_resources.py")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            res = root / "res"
            (res / "values").mkdir(parents=True)
            (res / "values/strings.xml").write_text(
                "<resources>" + "".join(f'<string name="{key}">{value}</string>' for key, value in default.items()) + "</resources>"
            )
            (root / "copy.json").write_text(json.dumps({"localizations": [{"locale": "zh-CN"}]}))
            with patch.object(resources, "ROOT", root), patch.object(resources, "RES", res), \
                 patch.object(resources, "IOS", root / "ios"), patch.object(resources, "REVIEWED", root / "reviewed"), \
                 contextlib.redirect_stdout(io.StringIO()):
                resources.main()
            self.assertEqual(reads, ["en.lproj", "zh-Hans.lproj"])
            self.assertTrue((res / "values-zh-rCN/gp_capture_strings.xml").exists())
            labels = json.loads((root / "capture-labels.json").read_text())
            self.assertEqual(labels["zh-CN"]["record_detail_score_trend"], "比分走势")


class GooglePlayCaptureEvidenceTests(unittest.TestCase):
    locale = "ja-JP"
    names = ["伊達政宗", "真田幸村"]
    labels = {"tab_score": "スコア", "tab_records": "記録", "tab_badminton": "バドミントン",
              "cancel": "キャンセル", "record_detail_score_trend": "得点の推移"}

    def fixture(self, repository):
        root = repository / "marketing/google-play/localization"
        folder = root / "captures" / self.locale
        folder.mkdir(parents=True)
        texts = self.names + list(self.labels.values())
        xml = '<hierarchy>' + ''.join(f'<node text="{html.escape(text)}" bounds="[0,0][10,10]" />' for text in texts) + '</hierarchy>'
        for filename in evidence.SOURCE_FILES:
            path = folder / filename
            if path.suffix == ".png":
                Image.new("RGB", (1080, 1920), "white").save(path)
            else:
                path.write_text(xml)
        legacy = {"locale": self.locale, "names": self.names, "labels": self.labels, "status": "verified", "androidLocale": "[ja-JP]"}
        evidence.write_capture_report(folder, legacy)
        entries = [{"file": path.relative_to(repository).as_posix(), **value}
                   for filename, value in evidence.source_manifest(folder, self.names, self.labels).items()
                   for path in [folder / filename]]
        inventory = repository / "audit.json"
        inventory.write_text(json.dumps(entries))
        copy_data = {self.locale: {"locale": self.locale, "playerNames": dict(zip(("score", "catalog"), self.names))}}
        (root / "metadata.json").write_text(json.dumps({"localizations": [{"language": self.locale, "uploadEligible": True}]}))
        (root / "copy.json").write_text(json.dumps({"localizations": list(copy_data.values())}))
        (root / "capture-labels.json").write_text(json.dumps({self.locale: self.labels}))
        return root, folder, xml, legacy, inventory, copy_data

    def testFailedAttemptImmediatelyInvalidatesPreviousSuccess(self):
        for failure in ("seed", "screenshot"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root, folder, xml, legacy, inventory, copy_data = self.fixture(Path(temporary))
                evidence.write_capture_report(folder, evidence.seal_capture_report(folder, legacy, self.locale, self.names, self.labels))
                def seed(*args):
                    self.assertFalse((folder / "verification.json").exists())
                    if failure == "seed":
                        raise capture.StepError("offline seed failure")
                def screenshot(path):
                    Image.new("RGB", (1080, 1920), "red").save(path)
                    raise capture.StepError("offline capture failure after overwrite")
                def sh(*args, **kwargs):
                    return "status=names set" if args[-1] == capture.HELPER else ""
                with patch.object(capture, "OUT", root / "captures"), patch.object(capture, "COPY", copy_data), \
                     patch.object(capture, "LABELS", {self.locale: self.labels}), patch.object(capture, "seed_database", side_effect=seed), \
                     patch.object(capture, "sh", side_effect=sh), patch.object(capture, "dump", return_value=xml), \
                     patch.object(capture, "tap_label"), patch.object(capture.time, "sleep"), patch.object(capture, "screenshot", side_effect=screenshot):
                    with self.assertRaises(capture.StepError):
                        capture.capture_locale(self.locale)
                self.assertFalse((folder / "verification.json").exists())

    def testSuccessfulCaptureSealsAllSixSources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, folder, xml, legacy, inventory, copy_data = self.fixture(Path(temporary))
            def sh(*args, **kwargs):
                if args[-1] == capture.HELPER:
                    return "status=names set"
                return "[ja-JP]" if "get-app-locales" in args else ""
            def screenshot(path):
                Image.new("RGB", (1080, 1920), "blue").save(path)
            with patch.object(capture, "OUT", root / "captures"), patch.object(capture, "COPY", copy_data), \
                 patch.object(capture, "LABELS", {self.locale: self.labels}), patch.object(capture, "seed_database"), \
                 patch.object(capture, "sh", side_effect=sh), patch.object(capture, "dump", return_value=xml), \
                 patch.object(capture, "tap_label"), patch.object(capture.time, "sleep"), patch.object(capture, "screenshot", side_effect=screenshot), \
                 contextlib.redirect_stdout(io.StringIO()):
                capture.capture_locale(self.locale)
            report = evidence.validate_capture_report(folder, self.locale, self.names, self.labels)
            self.assertEqual(report["schemaVersion"], evidence.SCHEMA_VERSION)
            self.assertEqual(set(report["sources"]), set(evidence.SOURCE_FILES))

    def testSinglePngOrXmlChangeIsRejectedByBothDownstreamEntrypoints(self):
        for filename in evidence.SOURCE_FILES:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temporary:
                root, folder, xml, legacy, inventory, copy_data = self.fixture(Path(temporary))
                evidence.write_capture_report(folder, evidence.seal_capture_report(folder, legacy, self.locale, self.names, self.labels))
                path = folder / filename
                if path.suffix == ".png":
                    Image.new("RGB", (1080, 1920), "red").save(path)
                else:
                    path.write_text(xml.replace("<hierarchy>", '<hierarchy changed="true">'))
                with patch.object(compositor, "ROOT", root), patch.object(compositor, "CAPS", root / "captures"), \
                     patch.object(compositor, "ASSETS", root / "assets/localized"), patch.object(compositor, "COPY", copy_data), \
                     patch.object(compositor, "LABELS", {self.locale: self.labels}), patch.object(compositor, "composite_04") as composite, \
                     patch.object(sys, "argv", ["composite_localized_bg.py", self.locale]):
                    with self.assertRaisesRegex(evidence.CaptureEvidenceError, "capture source changed"):
                        compositor.main()
                    composite.assert_not_called()
                    self.assertFalse((root / "assets/localized").exists())
                with patch.object(verifier, "ROOT", root), patch.object(sys, "argv", ["verify_localized_ui.py", self.locale]):
                    with self.assertRaisesRegex(evidence.CaptureEvidenceError, "capture source changed"):
                        verifier.main()
                    self.assertFalse((root / "localized-ui-verification.json").exists())

    def testCurrentCopyOrResourceChangesInvalidateEvidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            root, folder, xml, legacy, inventory, copy_data = self.fixture(Path(temporary))
            evidence.write_capture_report(folder, evidence.seal_capture_report(folder, legacy, self.locale, self.names, self.labels))
            with self.assertRaisesRegex(evidence.CaptureEvidenceError, "capture names differ"):
                evidence.validate_capture_report(folder, self.locale, ["別名", self.names[1]], self.labels)
            with self.assertRaisesRegex(evidence.CaptureEvidenceError, "capture labels differ"):
                evidence.validate_capture_report(folder, self.locale, self.names, dict(self.labels, cancel="変更"))

    def testSimplifiedChineseConsumerRejectsEachChangedSourceBeforeExportWork(self):
        for filename in evidence.SOURCE_FILES:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temporary, \
                 patch.object(self, "locale", "zh-CN"), patch.object(self, "names", ["陈冠廷", "林雅婷"]), \
                 patch.object(self, "labels", {"tab_score": "计分", "tab_records": "记录", "tab_badminton": "羽毛球",
                                               "cancel": "取消", "record_detail_score_trend": "比分走势"}):
                root, folder, xml, legacy, inventory, copy_data = self.fixture(Path(temporary))
                evidence.write_capture_report(folder, evidence.seal_capture_report(folder, legacy, self.locale, self.names, self.labels))
                path = folder / filename
                if path.suffix == ".png":
                    Image.new("RGB", (1080, 1920), "red").save(path)
                else:
                    path.write_text(xml.replace("<hierarchy>", '<hierarchy changed="true">'))
                with patch.object(chinese_verifier, "ROOT", root), patch.object(api, "local_plan") as plan, \
                     patch.object(api, "dump") as write, patch.object(chinese_verifier.Image, "new") as preview:
                    with self.assertRaisesRegex(evidence.CaptureEvidenceError, "capture source changed"):
                        chinese_verifier.main()
                    plan.assert_not_called()
                    write.assert_not_called()
                    preview.assert_not_called()
                    self.assertFalse((root / "preview-zh-CN.png").exists())

    def testLegacyUpgradeRequiresTrustedInventoryAndBacksUpMetadataWithoutDeviceCalls(self):
        with tempfile.TemporaryDirectory() as temporary:
            repository = Path(temporary)
            root, folder, xml, legacy, inventory, copy_data = self.fixture(repository)
            original = (folder / "verification.json").read_bytes()
            sources = {name: (folder / name).read_bytes() for name in evidence.SOURCE_FILES}
            with self.assertRaisesRegex(evidence.CaptureEvidenceError, "lacks source hashes"):
                evidence.validate_capture_report(folder, self.locale, self.names, self.labels)
            backup = repository / "backups"
            with patch.object(capture, "ROOT", root), patch.object(capture, "COPY", copy_data), \
                 patch.object(capture, "LABELS", {self.locale: self.labels}), patch.object(capture, "sh") as device, \
                 patch.object(sys, "argv", ["capture_localized_gp.py", "--upgrade-evidence", "--inventory", str(inventory), "--backup-dir", str(backup), self.locale]), \
                 contextlib.redirect_stdout(io.StringIO()):
                capture.main()
                device.assert_not_called()
            self.assertEqual((backup / (folder / "verification.json").relative_to(repository)).read_bytes(), original)
            report = evidence.validate_capture_report(folder, self.locale, self.names, self.labels)
            self.assertEqual(report["evidenceOrigin"], "legacy-offline-inventory-upgrade")
            self.assertTrue(report["auditInventorySha256"])
            self.assertEqual(sources, {name: (folder / name).read_bytes() for name in evidence.SOURCE_FILES})

    def testLegacyUpgradeRejectsMissingSnapshotOrChangedSourceWithoutWrites(self):
        for corrupt in ("missing", "changed"):
            with self.subTest(corrupt=corrupt), tempfile.TemporaryDirectory() as temporary:
                repository = Path(temporary)
                root, folder, xml, legacy, inventory, copy_data = self.fixture(repository)
                original = (folder / "verification.json").read_bytes()
                if corrupt == "missing":
                    inventory.write_text("[]")
                else:
                    Image.new("RGB", (1080, 1920), "red").save(folder / "05.png")
                backup = repository / "backups"
                with self.assertRaisesRegex(evidence.CaptureEvidenceError, "trusted inventory missing or changed"):
                    evidence.upgrade_evidence(root, [self.locale], copy_data, {self.locale: self.labels}, inventory, backup)
                self.assertEqual((folder / "verification.json").read_bytes(), original)
                self.assertFalse(backup.exists())


if __name__ == "__main__":
    unittest.main()
