"""Exercise screenshot workflows with temporary files and mocked capture/render calls."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

WORKFLOW = Path(__file__).resolve().parents[1] / "marketing/app-store/ios-screenshots-pen-2026-10-02"

# This historical screenshot bundle is not tracked in the repository.
# Skip before importing it (or its imaging dependencies), but let incomplete or
# broken bundles fail normally when the directory is present.
if not WORKFLOW.is_dir():
    raise unittest.SkipTest(f"Optional iOS screenshot workflow is not in this checkout: {WORKFLOW}")

from PIL import Image, ImageDraw


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, WORKFLOW / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


capture = load_module("offline_ios_capture", "capture_localized.py")
with patch.dict(sys.modules, {"capture_localized": capture}), patch.object(sys, "path", list(sys.path)):
    chinese = load_module("offline_ios_chinese_capture", "capture_zh.py")


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False))


class CaptureWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name)
        self.root = self.project / "marketing/app-store/screenshots"
        self.out = self.project / "artifacts/capture-run"
        write_json(self.root / "player-names.json", {"localizations": [
            {"locale": "en-US", "names": ["Ethan", "Liam"], "fontFamily": "Poppins"},
            {"locale": "zh-Hant", "names": ["陳冠廷", "林雅婷"], "fontFamily": "Noto Sans TC"},
        ]})
        write_json(self.root.parent / "localization-2026-10-02/locale-map.json", {"locales": [
            {"locale": "en-US", "iosLocale": "en"}, {"locale": "zh-Hant", "iosLocale": "zh-Hant"},
        ]})
        write_json(self.root / "basketball-teams.json", {"localizations": [
            {"locale": "en-US", "names": ["Home", "Away"]},
            {"locale": "zh-Hant", "names": ["主隊", "客隊"]},
        ]})
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        for name, value in [("ROOT", self.root), ("PROJECT", self.project), ("OUT", self.out), ("SIM", "offline-sim")]:
            stack.enter_context(patch.object(capture, name, value))
        stack.enter_context(patch.object(chinese, "HERE", self.root))
        stack.enter_context(patch.object(capture, "command", side_effect=AssertionError("Real simulator access is forbidden")))

    def fake_capture(self, entry, scene):
        folder = self.out / entry["locale"]
        folder.mkdir(parents=True, exist_ok=True)
        file = folder / (scene + ".png")
        size = (2868, 1320) if scene in ("basketball", "multi", "snooker", "rally") else (1320, 2868)
        Image.new("RGB", size, "white").save(file)
        result = {"scene": scene, "file": str(file.relative_to(self.project)), "width": size[0], "height": size[1],
                  "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
        if scene == "basketball":
            result["teamNames"] = entry["basketballTeams"]
        return result

    def seed_manifest(self):
        entry = capture.config()[0]
        manifest = {**entry, "simulator": "offline-sim", "screens": [self.fake_capture(entry, scene) for scene in capture.SCENES]}
        file = self.out / entry["locale"] / "manifest.json"
        write_json(file, manifest)
        return entry, file, manifest

    def run_main(self, arguments):
        with patch.object(sys, "argv", ["capture_localized.py", *arguments]), \
             patch.object(capture, "capture", side_effect=self.fake_capture) as mocked, \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            capture.main()
        return mocked

    def testEnglishSelectionStillBuildsTraditionalChineseConfiguration(self):
        mocked = self.run_main(["--locales", "en-US", "--scenes", "record"])
        self.assertEqual([(call.args[0]["locale"], call.args[1]) for call in mocked.call_args_list], [("en-US", "record")])
        data = json.loads((self.root / "capture-config.json").read_text())
        entry = next(item for item in data["localizations"] if item["locale"] == "zh-Hant")
        self.assertEqual(entry["names"], ["陳冠廷", "林雅婷", "王宗翰", "黃淑芬"])
        self.assertEqual(entry["appleLanguage"], "zh-Hant")
        self.assertEqual(entry["appleLocale"], "zh_TW")

    def testUnknownLocaleAndSceneFailBeforeWritingConfiguration(self):
        config = self.root / "capture-config.json"
        config.write_text("unchanged configuration")
        for arguments in (["--locales", "unknown"], ["--scenes", "unknown"]):
            with self.subTest(arguments=arguments):
                with self.assertRaises(SystemExit) as raised:
                    self.run_main(arguments)
                self.assertEqual(raised.exception.code, 2)
                self.assertEqual(config.read_text(), "unchanged configuration")
                self.assertFalse(self.out.exists())

    def testResumeReusesOnlyMatchingConfigurationAndImageHashes(self):
        self.seed_manifest()
        mocked = self.run_main(["--locales", "en-US", "--resume"])
        mocked.assert_not_called()

    def testChangedConfigurationRecapturesEveryScene(self):
        entry, file, baseline = self.seed_manifest()
        changes = {"locale": "old-locale", "appleLanguage": "old-language", "appleLocale": "old-region",
                   "names": ["Old", "Names"], "basketballTeams": ["Old", "Teams"]}
        for key, changed in changes.items():
            with self.subTest(key=key):
                prior = copy.deepcopy(baseline)
                prior[key] = changed
                write_json(file, prior)
                mocked = self.run_main(["--locales", "en-US", "--scenes", "record", "--resume"])
                self.assertEqual([call.args[1] for call in mocked.call_args_list], capture.SCENES)
                updated = json.loads(file.read_text())
                self.assertTrue(capture.matches_configuration(updated, entry))
                self.assertEqual(len(updated["screens"]), 7)

    def testChangedImageRecapturesOnlyItsScene(self):
        _, file, manifest = self.seed_manifest()
        screen = next(item for item in manifest["screens"] if item["scene"] == "setup")
        (self.project / screen["file"]).write_bytes(b"replaced PNG")
        mocked = self.run_main(["--locales", "en-US", "--resume"])
        self.assertEqual([call.args[1] for call in mocked.call_args_list], ["setup"])
        self.assertTrue(all(capture.screen_is_current(item) for item in json.loads(file.read_text())["screens"]))

    def testResumeRejectsWrongDimensionsAndPathsOutsideProject(self):
        _, _, manifest = self.seed_manifest()
        screen = copy.deepcopy(manifest["screens"][0])
        screen["width"] = 1
        self.assertFalse(capture.screen_is_current(screen))
        screen = copy.deepcopy(manifest["screens"][0])
        file = self.project / screen["file"]
        Image.new("RGB", (64, 64), "white").save(file)
        screen["sha256"] = hashlib.sha256(file.read_bytes()).hexdigest()
        self.assertFalse(capture.screen_is_current(screen))
        screen["file"] = "../../outside.png"
        self.assertFalse(capture.screen_is_current(screen))

    def testChineseCaptureWritesAllSevenSceneHashesAndPreservesOtherLocales(self):
        write_json(self.root / "capture-config.json", {"localizations": [{"locale": "en-US"}, {"locale": "zh-Hant", "old": True}]})
        with patch.object(capture, "capture", side_effect=self.fake_capture) as mocked, contextlib.redirect_stdout(io.StringIO()):
            chinese.main()
        self.assertEqual(mocked.call_count, 7)
        manifest = json.loads((self.out / "zh-Hant/manifest.json").read_text())
        self.assertEqual(manifest["simulator"], "offline-sim")
        self.assertTrue(capture.matches_configuration(manifest, chinese.ENTRY))
        self.assertEqual([item["scene"] for item in manifest["screens"]], capture.SCENES)
        self.assertTrue(all(capture.screen_is_current(item) for item in manifest["screens"]))
        config = json.loads((self.root / "capture-config.json").read_text())["localizations"]
        self.assertEqual([item["locale"] for item in config], ["en-US", "zh-Hant"])


class PreviewWorkflowTests(unittest.TestCase):
    def testVisibleNamesPreviewIncludesTheFortyNinthLocale(self):
        entries = [{"locale": "fixture-" + str(index)} for index in range(48)] + [{"locale": "zh-Hant"}]
        saved, opened = [], []

        class FakeImage:
            def crop(self, box): return self
            def resize(self, size): return self
            def thumbnail(self, size): pass
            def paste(self, image, position): pass
            def save(self, path): saved.append(str(path))

        def image_open(path):
            opened.append(str(path))
            return FakeImage()

        with patch.object(Path, "read_text", return_value=json.dumps({"localizations": entries})), \
             patch.object(Image, "new", side_effect=lambda *args, **kwargs: FakeImage()), \
             patch.object(Image, "open", side_effect=image_open), patch.object(ImageDraw, "Draw", return_value=Mock()):
            runpy.run_path(str(WORKFLOW / "preview-visible-names.py"), run_name="offline_preview")
        self.assertEqual(len(saved), 5)
        self.assertTrue(any("zh-Hant" in path for path in opened))

    @unittest.skipUnless(shutil.which("node"), "Node is needed for the CJS offline renderer mock")
    def testPlayerNamesPreviewIncludesTheFortyNinthLocale(self):
        program = r"""
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(process.argv[1],'utf8');
const entries=Array.from({length:49},(_,i)=>({locale:i===48?'zh-Hant':'fixture-'+i}));
const batches=[];
function sharp(input){return {items:[],extract(){return this},resize(){return this},png(){return this},
 toBuffer(){return Promise.resolve(Buffer.from(String(input)))},composite(items){this.items=items;return this},
 toFile(file){batches.push({file,items:this.items.map(item=>item.input.toString())});return Promise.resolve()}}}
vm.runInNewContext(source,{__dirname:'/offline',Buffer,console,require(name){
 if(name==='fs')return {readFileSync(){return Buffer.from(JSON.stringify({localizations:entries}))}};
 if(name==='path')return path;
 if(name.endsWith('/sharp'))return sharp;
 throw new Error('Unexpected require: '+name);
}});
setImmediate(()=>process.stdout.write(JSON.stringify(batches)));
"""
        result = subprocess.run([shutil.which("node"), "-e", program, str(WORKFLOW / "preview-names.cjs")],
                                check=True, capture_output=True, text=True, timeout=10)
        batches = json.loads(result.stdout)
        self.assertEqual(len(batches), 5)
        self.assertTrue(any("zh-Hant" in item for item in batches[-1]["items"]))


if __name__ == "__main__":
    unittest.main()
