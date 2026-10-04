#!/usr/bin/env python3
import importlib.util
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("localize.py")
SPEC = importlib.util.spec_from_file_location("jifen_localize", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
localize = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = localize
SPEC.loader.exec_module(localize)


class LocalizationPipelineTests(unittest.TestCase):
    def run_hant_generator(self, directory, overrides):
        directory = Path(directory)
        (directory / "hans.strings").write_text('"voice_announce_server" = "播报发球方";\n')
        (directory / "android.xml").write_text('<resources/>')
        (directory / "terms.json").write_text(json.dumps({
            "replacements": [], "platformKeyPrefixes": ["^ios_"], "simplifiedResidue": []
        }))
        (directory / "overrides.json").write_text(json.dumps(overrides))
        return subprocess.run([
            shutil.which("node"), str(MODULE_PATH.with_name("gen_zh_hant.mjs")),
            "--converter", "identity", "--ios-hans", str(directory / "hans.strings"),
            "--android-cn", str(directory / "android.xml"), "--android-tw", str(directory / "android.xml"),
            "--terms", str(directory / "terms.json"), "--overrides", str(directory / "overrides.json"),
            "--out", str(directory / "output.strings"), "--report", str(directory / "report.md")
        ], capture_output=True, text=True)

    @unittest.skipUnless(shutil.which("node"), "Node is required for generator regression")
    def test_hant_generator_preserves_reviewed_override(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_hant_generator(directory, {"voice_announce_server": {"value": "播報發球方"}})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"voice_announce_server" = "播報發球方";', (Path(directory) / "output.strings").read_text())

    @unittest.skipUnless(shutil.which("node"), "Node is required for generator regression")
    def test_hant_generator_rejects_malformed_override_before_writing(self):
        for value in ["播報發球方", None, {}, {"value": 1}]:
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "output.strings"
                output.write_text("previous reviewed output")
                result = self.run_hant_generator(directory, {"voice_announce_server": value})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid override for voice_announce_server", result.stderr)
                self.assertEqual(output.read_text(), "previous reviewed output")
                self.assertFalse((Path(directory) / "report.md").exists())

    def test_manifest_has_expected_matrix(self):
        payload = localize.manifest()
        locales = payload["locales"]
        self.assertEqual(len(locales), 47)
        self.assertEqual(len([item for item in locales if not item["existing"]]), 44)
        self.assertEqual(len({item["ios"] for item in locales}), 47)
        self.assertEqual([item["ios"] for item in locales if item["rtl"]], ["ar", "he", "ur"])

    def test_source_inventory(self):
        entries = localize.source_entries()
        self.assertEqual(len([entry for entry in entries if entry.table == "Localizable"]), 1449)
        self.assertEqual(len([entry for entry in entries if entry.table == "InfoPlist"]), 4)
        self.assertEqual(len({entry.identity for entry in entries}), 1453)
        self.assertTrue({("Localizable", "feedback_official"), ("Localizable", "feedback_pinned"),
                         ("Localizable", "voice_announce_server"),
                         ("Localizable", "scoreboard_official_break_help_intro"),
                         ("Localizable", "scoreboard_official_break_rule_between_games_60"),
                         ("Localizable", "scoreboard_official_break_rule_badminton"),
                         ("Localizable", "scoreboard_official_break_rule_squash"),
                         ("Localizable", "scoreboard_official_break_rule_tennis"),
                         ("Localizable", "scoreboard_official_break_rule_soft_tennis"),
                         ("Localizable", "scoreboard_official_break_rule_pickleball")}
                        .issubset({entry.identity for entry in entries}))

    def test_promoted_resources_match_reviewed_catalogs(self):
        # A reviewed catalog and the app can both validate separately yet carry
        # different text when only one side of a correction is saved.
        for spec in localize.manifest()["locales"]:
            locale = spec["ios"]
            folder = localize.RESOURCE_ROOT / (locale + ".lproj")
            if spec["existing"] or not folder.exists():
                continue
            catalog = localize.load_catalog(locale)
            for table in ["Localizable", "InfoPlist"]:
                actual = {entry.key: entry.value for entry in localize.parse_strings(folder / (table + ".strings"), table)}
                expected = {entry.key: localize.value_for_row(catalog[entry.identity])
                            for entry in localize.source_entries() if entry.table == table}
                self.assertEqual(actual, expected, f"{locale}/{table} differs from the reviewed catalog")
            actual_plurals = plistlib.loads((folder / "Localizable.stringsdict").read_bytes())
            expected_plurals = plistlib.loads(localize.render_stringsdict(locale, catalog))
            self.assertEqual(actual_plurals, expected_plurals, f"{locale} plurals differ from the reviewed catalog")

    def test_plural_inventory_uses_locale_categories(self):
        plural_count = len(localize.plural_manifest()["keys"])
        self.assertEqual(len(localize.plural_entries("ja")), plural_count)
        self.assertEqual(len(localize.plural_entries("ar")), plural_count * 6)
        self.assertEqual(
            {entry.key.rsplit(".", 1)[1] for entry in localize.plural_entries("ru")},
            {"one", "few", "many", "other"},
        )

    def test_apple_string_codec_round_trips(self):
        source = 'Quote " slash \\ newline\n tab\t 中文'
        encoded = localize.encode_apple_string(source)
        self.assertEqual(localize.decode_apple_string(encoded), source)

    def test_protected_spans_round_trip(self):
        source = "Apple saved %1$d of %2$d at https://example.com/a?b=1\nDone"
        wrapped, mapping = localize.protected_spans(source, ["Apple"])
        self.assertIn('translate="no"', wrapped)
        self.assertEqual(localize.restore_protected(wrapped, mapping), source)

    def test_protected_spans_reject_missing_marker(self):
        _, mapping = localize.protected_spans("Score %d", [])
        with self.assertRaises(ValueError):
            localize.restore_protected("Score", mapping)

    def test_protected_tokens_round_trip(self):
        source = "Apple score %1$d\nhttps://example.com"
        wrapped, mapping = localize.protected_tokens(source, ["Apple"])
        self.assertNotIn("Apple score", wrapped)
        self.assertRegex(wrapped, r"<JFP0000_ZXQ>")
        self.assertEqual(localize.restore_protected_tokens(wrapped, mapping), source)

    def test_format_signature_allows_explicit_reordering(self):
        source, source_mixed = localize.format_arguments("%d players, %@ team")
        target, target_mixed = localize.format_arguments("%2$@ — %1$d")
        self.assertFalse(source_mixed)
        self.assertFalse(target_mixed)
        self.assertEqual(source, target)

    def test_format_signature_rejects_type_change(self):
        source, _ = localize.format_arguments("%d players")
        target, _ = localize.format_arguments("%@ players")
        self.assertNotEqual(source, target)

    def test_machine_candidate_normalizes_provider_edge_whitespace(self):
        row = {"google_web": "  Puntuación  ", "azure": None}
        self.assertEqual(localize.machine_candidate(row), "Puntuación")

        decomposed = "  e\u0301  "
        self.assertEqual(localize.machine_candidate({"azure": decomposed}), "é")

    def test_render_preserves_template_shape(self):
        source = localize.parse_strings(localize.SOURCE_INFO_PLIST, "InfoPlist")
        catalog = {}
        for entry in source:
            catalog[entry.identity] = {
                "table": entry.table,
                "key": entry.key,
                "source_hash": entry.source_hash,
                "azure": "iScoreboard" if entry.key == "CFBundleDisplayName" else "Translated " + entry.key,
                "final": "iScoreboard" if entry.key == "CFBundleDisplayName" else "Translated " + entry.key,
                "status": "reviewed",
            }
        rendered = localize.render_strings(localize.SOURCE_INFO_PLIST, "InfoPlist", catalog)
        self.assertIn('"CFBundleDisplayName" = "iScoreboard";', rendered)
        self.assertEqual(rendered.count(" = "), 4)

    def test_catalog_jsonl_order_follows_source(self):
        entries = localize.source_entries("ja")
        catalog = {}
        for entry in reversed(entries):
            catalog[entry.identity] = {
                "table": entry.table,
                "key": entry.key,
                "source_hash": entry.source_hash,
                "azure": entry.value,
                "google": None,
                "final": entry.value,
                "status": "reviewed",
                "flags": [],
                "note": None,
            }
        original_root = localize.CATALOG_ROOT
        with tempfile.TemporaryDirectory() as directory:
            localize.CATALOG_ROOT = Path(directory)
            try:
                localize.write_catalog("ja", catalog)
                lines = (Path(directory) / "ja.jsonl").read_text(encoding="utf-8").splitlines()
                first = json.loads(lines[0])
                last = json.loads(lines[-1])
                self.assertEqual((first["table"], first["key"]), entries[0].identity)
                self.assertEqual((last["table"], last["key"]), entries[-1].identity)
            finally:
                localize.CATALOG_ROOT = original_root

    def test_reviewed_sentence_spaces_survive_catalog_and_resource_round_trip(self):
        catalog = localize.load_catalog("fr")
        fragments = {
            "vip_agreement_plain_prefix": "J’ai lu et j’accepte : ",
            "vip_agreement_link_separator": " et ",
            "vip_agreement_link_middle_separator": ", ",
            "setup_suffix": " Configuration",
            "doudizhu_winner_separator": ", ",
        }
        for key, value in fragments.items():
            catalog[("Localizable", key)]["final"] = value
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(localize, "CATALOG_ROOT", root):
                localize.write_catalog("fr", catalog)
                reloaded = localize.load_catalog("fr")
                self.assertTrue(localize.validate_locale("fr", True)["passed"])
                resource = root / "Localizable.strings"
                resource.write_text(localize.render_strings(localize.SOURCE_LOCALIZABLE, "Localizable", reloaded))
                values = {entry.key: entry.value for entry in localize.parse_strings(resource, "Localizable")}
                for key, value in fragments.items():
                    self.assertEqual(values[key], value)
                self.assertEqual("Échecs" + values["setup_suffix"], "Échecs Configuration")
                self.assertEqual(values["doudizhu_winner_separator"].join(["Alice", "Bob"]), "Alice, Bob")
                # Check the same four combinations as the membership page:
                # signed in/out, subscription/lifetime.
                for signed_out in [False, True]:
                    for subscription in [False, True]:
                        links = (["vip_user_agreement_link"] if signed_out else [])
                        links += (["vip_auto_renew_terms_link"] if subscription else [])
                        links += ["vip_membership_agreement_link"]
                        sentence = values["vip_agreement_plain_prefix"]
                        for index, key in enumerate(links):
                            if index:
                                separator = "vip_agreement_link_separator" if index == len(links) - 1 else "vip_agreement_link_middle_separator"
                                sentence += values[separator]
                            sentence += values[key]
                        self.assertIn(": " + values[links[0]], sentence)
                        if len(links) > 1:
                            self.assertIn(" et " + values[links[-1]], sentence)

    def test_sentence_space_exception_does_not_allow_accidental_padding(self):
        cases = [
            ("vip_agreement_link_separator", " et ", False),
            ("vip_agreement_link_separator", "  et ", True),
            ("vip_agreement_link_separator", "\tet ", True),
            ("vip_agreement_plain_prefix", "Texte\n", True),
            ("setup_suffix", " Configuration", False),
            ("setup_suffix", "  Configuration", True),
            ("doudizhu_winner_separator", ", ", False),
            ("doudizhu_winner_separator", ",\t", True),
            ("cancel", " Annuler ", True),
        ]
        for key, value, should_block in cases:
            with self.subTest(key=key, value=value):
                catalog = localize.load_catalog("fr")
                catalog[("Localizable", key)]["final"] = value
                with patch.object(localize, "load_catalog", return_value=catalog):
                    blockers = localize.validate_locale("fr", True)["blockers"]
                self.assertEqual(any(row["code"] == "edge-whitespace" and row["key"] == key for row in blockers), should_block)

    def test_source_urls_survive_translation_and_sentence_cleanup(self):
        identity = ("Localizable", "sync_intro_note")
        cases = [
            ("Consultez (https://jifenqi.com).", False),
            ("Consultez «https://jifenqi.com».", False),
            ("ウェブサイト（https://jifenqi.com）を開きます。", False),
            ("웹사이트(https://jifenqi.com)를 여세요.", False),
            ("موقعنا (https://jifenqi.com)،", False),
            ("Consultez (https://jifenqi. com).", True),
            ("Consultez (https://jifenqi.com.example).", True),
            ("Consultez notre site.", True),
        ]
        for value, should_block in cases:
            with self.subTest(value=value):
                catalog = localize.load_catalog("fr")
                catalog[identity]["final"] = value
                with patch.object(localize, "load_catalog", return_value=catalog):
                    blockers = localize.validate_locale("fr", True)["blockers"]
                self.assertEqual(any(row["code"] == "protected-url" and row["key"] == identity[1] for row in blockers), should_block)

    def test_pipe_residue_is_a_blocking_provider_artifact(self):
        catalog = localize.load_catalog("fr")
        identity = ("Localizable", "cancel")
        self.assertNotIn(localize.PIPE_ARTIFACT, localize.source_by_identity("fr")[identity].value)
        catalog[identity]["final"] = "Annuler" + localize.PIPE_ARTIFACT
        catalog[identity]["status"] = "reviewed"
        with patch.object(localize, "load_catalog", return_value=catalog):
            blockers = localize.validate_locale("fr", True)["blockers"]
        self.assertTrue(any(row["code"] == "provider-artifact" and row["key"] == "cancel" for row in blockers))

    def test_cjk_word_spacing_is_a_blocking_reviewed_artifact(self):
        catalog = localize.load_catalog("it")
        identity = ("Localizable", "sync_players_format")
        self.assertNotIn("  ", localize.source_by_identity("it")[identity].value)
        catalog[identity]["final"] = "Giocatori  %d"
        catalog[identity]["status"] = "reviewed"
        with patch.object(localize, "load_catalog", return_value=catalog):
            blockers = localize.validate_locale("it", True)["blockers"]
        self.assertTrue(any(row["code"] == "internal-multi-space" and row["key"] == "sync_players_format" for row in blockers))

    def test_no_reviewed_final_ships_double_spaces(self):
        # Providers copied the Chinese source's inter-word double space into reviewed strings.
        # Machine drafts may still carry it; a reviewed value is what renders on screen.
        offenders = []
        for path in sorted(localize.CATALOG_ROOT.glob("*.jsonl")):
            source = localize.source_by_identity(path.stem)
            for row in localize.load_catalog(path.stem).values():
                if row.get("status") not in localize.REVIEW_STATES:
                    continue
                value = row.get("final")
                entry = source.get((row["table"], row["key"]))
                if not isinstance(value, str) or entry is None:
                    continue
                if "  " in value and "  " not in entry.value:
                    offenders.append((path.stem, row["table"], row["key"], value))
        self.assertEqual(offenders, [])

    def test_punctuation_glue_is_a_blocking_reviewed_artifact(self):
        # Providers drop the space after sentence punctuation, which renders as one glued word.
        # Single-letter abbreviations and Romance ordinals must stay legal, or the gate would
        # block copy nobody wants changed.
        self.assertEqual(localize.punctuation_glue("ad es. al meglio di cinque"), [])
        self.assertEqual(localize.punctuation_glue("1.º y 2.º puestos (+3)"), [])
        self.assertEqual(localize.punctuation_glue("https://jifenqi.com funziona"), [])
        self.assertEqual(len(localize.punctuation_glue("Eliminato?Questa azione")), 1)
        catalog = localize.load_catalog("it")
        identity = ("Localizable", "confirm_delete_record_message")
        catalog[identity]["final"] = "Sei sicuro di voler eliminare?Questa azione non può essere annullata."
        catalog[identity]["status"] = "reviewed"
        with patch.object(localize, "load_catalog", return_value=catalog):
            blockers = localize.validate_locale("it", True)["blockers"]
        self.assertTrue(any(row["code"] == "punctuation-glue" and row["key"] == identity[1] for row in blockers))

    def test_no_reviewed_final_ships_punctuation_glue(self):
        offenders = []
        for path in sorted(localize.CATALOG_ROOT.glob("*.jsonl")):
            for row in localize.load_catalog(path.stem).values():
                if row.get("status") not in localize.REVIEW_STATES:
                    continue
                value = row.get("final")
                if isinstance(value, str) and localize.punctuation_glue(value):
                    offenders.append((path.stem, row["table"], row["key"], localize.punctuation_glue(value)[0]))
        self.assertEqual(offenders, [])

    def test_no_catalog_hides_provider_pipe_residue(self):
        # Two separate guarantees: a reviewer-approved value may never ship the provider's
        # multi-candidate separator, and a row nobody looked at may not carry that residue in
        # any field (its draft is still the only thing a later packet would read).
        shipped = []
        unreviewed = []
        for path in sorted(localize.CATALOG_ROOT.glob("*.jsonl")):
            for row in localize.load_catalog(path.stem).values():
                if isinstance(row.get("final"), str) and localize.PIPE_ARTIFACT in row["final"]:
                    shipped.append((path.stem, row["table"], row["key"]))
                if row.get("status") not in localize.REVIEW_STATES:
                    for field in ("azure", "google", "google_web"):
                        value = row.get(field)
                        if isinstance(value, str) and localize.PIPE_ARTIFACT in value:
                            unreviewed.append((path.stem, row["table"], row["key"], field))
        self.assertEqual(shipped, [])
        self.assertEqual(unreviewed, [])

    def test_promoted_resources_never_ship_an_unreviewed_catalog_row(self):
        # Promotion appends knownRegions and renders .lproj, so a locale that has
        # resources in the bundle must have a fully reviewed catalog. Without this the
        # half-promoted locale ships machine drafts and no Xcode gate notices.
        shipped_unreviewed = []
        for catalog_path in sorted(localize.CATALOG_ROOT.glob("*.jsonl")):
            locale = catalog_path.stem
            if not (localize.RESOURCE_ROOT / (locale + ".lproj") / "Localizable.strings").exists():
                continue
            catalog = localize.load_catalog(locale)
            expected = {entry.identity for entry in localize.source_entries(locale)}
            self.assertEqual(set(catalog), expected, "%s catalog keys must match source" % locale)
            for identity, row in catalog.items():
                if row.get("status") not in localize.REVIEW_STATES:
                    shipped_unreviewed.append((locale, identity[0], identity[1]))
        self.assertEqual(shipped_unreviewed, [])


    def test_visual_audit_report_covers_every_promoted_locale(self):
        # Promotion renders .lproj, and the screenshot audit is the only place a human
        # actually looks at the shipped strings. Its locale list is a separate hardcoded
        # array in the report generator, so a new promotion silently ships unviewed.
        generator = localize.REPO_ROOT / "scripts" / "generate_localization_visual_audit.js"
        source = generator.read_text(encoding="utf-8")
        block = source.split("const locales = [", 1)[1].split("];", 1)[0]
        listed = set(re.findall(r'\["([a-zA-Z0-9_-]+)",\s*"[^"]+",\s*"(?:LTR|RTL)"\]', block))
        # en and the two Chinese variants are the development/base localizations: the
        # source copy is written in them, so a screenshot of them proves nothing.
        source_languages = {"en", "zh_Hans", "zh_Hant"}
        shipped = {
            path.parent.name.replace(".lproj", "").replace("-", "_")
            for path in localize.RESOURCE_ROOT.glob("*.lproj/Localizable.strings")
        }
        self.assertEqual(sorted(shipped - source_languages - listed), [])


if __name__ == "__main__":
    unittest.main()
