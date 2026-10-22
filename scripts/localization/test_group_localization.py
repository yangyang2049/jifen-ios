"""Regression gates for group copy, independent of the copy writer."""
import json
import plistlib
import re
import unittest
import unicodedata
from pathlib import Path

import localize
from group_copy_20261017 import DATA_PATH, ROOT, table, planned_tables


class GroupLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.copy = json.loads(DATA_PATH.read_text())
        cls.tables = {locale: table(locale) for locale in localize.locale_map()}
        cls.english = cls.tables["en"]
        cls.shared = {"activity_direct_match_count", "archived_count"}
        cls.references = set()
        for path in (ROOT / "jifen/Features/Groups").glob("*.swift"):
            cls.references.update(re.findall(r'NSLocalizedString\("([^"]+)"', path.read_text()))

    @classmethod
    def related(cls, key):
        base = key.split(".", 1)[0]
        return key.startswith("group_") or base in cls.references or base in cls.shared

    def test_all_shipped_locales_have_matching_keys_and_safe_formats(self):
        expected = {key for key in self.english if self.related(key)}
        for locale, entries in self.tables.items():
            self.assertEqual({key for key in entries if self.related(key)}, expected, locale)
            for key in expected:
                source, value = self.english[key].value, entries[key].value
                self.assertTrue(value.strip(), (locale, key))
                self.assertEqual(localize.format_arguments(value), localize.format_arguments(source), (locale, key))
                self.assertEqual(value.count("\n"), source.count("\n"), (locale, key))

    def test_source_edits_cannot_be_silently_marked_reviewed(self):
        copy = dict(self.copy)
        copy['reviewed_sources'] = dict(copy['reviewed_sources'], group_archive_hint='Old archive meaning')
        with self.assertRaisesRegex(AssertionError, 'source changed after copy review'):
            planned_tables(copy)

    def test_every_locale_explains_lineup_counts_and_has_view_and_notice_labels(self):
        for locale, entries in self.tables.items():
            for key in ['group_multi_match_hint', 'group_single_match_hint',
                        'group_copy_activity_multi_match_hint', 'group_copy_activity_single_match_hint']:
                self.assertIn('2', entries[key].value, (locale, key))
                self.assertIn('4', entries[key].value, (locale, key))
            for key in ['group_view_schedule', 'group_notice_training_published',
                        'group_notice_training_changed', 'group_notice_training_cancelled', 'group_notice_leave_changed']:
                self.assertIn(key, entries, (locale, key))
                if locale != 'en':
                    self.assertNotEqual(entries[key].value, self.english[key].value, (locale, key))

    def test_explicit_audit_review_still_matches_sources_and_translations(self):
        review = json.loads(DATA_PATH.with_name('group-copy-review-20261021.json').read_text())
        for key, source in review['sources'].items():
            self.assertEqual(source, self.english[key].value, key)
        for locale, values in review['locales'].items():
            for key, value in values.items():
                self.assertEqual(value, self.tables[locale][key].value, (locale, key))

    def test_english_sentences_cannot_be_copied_into_other_languages(self):
        # These are reviewed shared words, native abbreviations and sports terms,
        # e.g. French "Source", Dutch "Training" and the minute symbol "min".
        approved = self.copy["shared_terms"]
        for locale, entries in self.tables.items():
            if locale in {"en", "zh-Hans", "zh-Hant"}:
                continue
            for key, entry in entries.items():
                if not (key.startswith("group_") or key in self.shared) or entry.value != self.english[key].value:
                    continue
                item = approved.get(key, {})
                self.assertEqual(item.get("value"), entry.value, (locale, key))
                self.assertIn(locale, item.get("locales", []), (locale, key))

    def test_south_asian_locales_do_not_use_another_locales_script(self):
        script_ranges = {"hi": (0x900, 0x97f), "mr": (0x900, 0x97f),
                         "bn": (0x980, 0x9ff), "pa": (0xa00, 0xa7f),
                         "gu": (0xa80, 0xaff), "or": (0xb00, 0xb7f),
                         "ta": (0xb80, 0xbff), "te": (0xc00, 0xc7f),
                         "kn": (0xc80, 0xcff), "ml": (0xd00, 0xd7f)}
        for locale, (first, last) in script_ranges.items():
            for key, entry in self.tables[locale].items():
                if self.related(key):
                    wrong = {char for char in entry.value if 0x900 <= ord(char) <= 0xd7f
                             and unicodedata.category(char)[0] in {"L", "M"}
                             and not first <= ord(char) <= last}
                    self.assertFalse(wrong, (locale, key, wrong))

    def test_group_review_catalogs_are_complete_fresh_and_match_shipped_copy(self):
        for locale, entries in self.tables.items():
            if locale in {"en", "zh-Hans", "zh-Hant"}:
                continue
            report = localize.validate_locale(locale, require_reviewed=True)
            group_blockers = [row for row in report["blockers"] if self.related(row.get("key") or "")]
            self.assertEqual(group_blockers, [], locale)
            catalog = localize.load_catalog(locale)
            for key, entry in entries.items():
                if self.related(key):
                    self.assertEqual(catalog[("Localizable", key)]["final"], entry.value, (locale, key))

    def test_shared_counter_plural_forms_are_localized_and_match_catalogs(self):
        for locale in self.tables:
            forms = plistlib.loads((ROOT / ("jifen/Resources/%s.lproj/Localizable.stringsdict" % locale)).read_bytes())
            catalog = None if locale in {"en", "zh-Hans", "zh-Hant"} else localize.load_catalog(locale)
            for key in self.shared:
                self.assertEqual(forms[key]["NSStringLocalizedFormatKey"], "%#@count@")
                count = forms[key]["count"]
                categories = set(localize.locale_map()[locale]["plural_categories"])
                self.assertEqual(set(count) - {"NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"}, categories)
                for category in categories:
                    value = count[category]
                    self.assertEqual(localize.format_arguments(value), localize.format_arguments("%d"))
                    if locale != "en":
                        self.assertNotIn("all group members", value)
                        self.assertNotIn(" groups", value)
                    if catalog is not None:
                        self.assertEqual(catalog[("Plural", key + "." + category)]["final"], value)

    def test_every_mapped_error_key_is_shipped_in_every_locale(self):
        source = (ROOT / "jifen/Features/Groups/GroupErrorMessage.swift").read_text()
        keys = set(re.findall(r'"[A-Z_]+":\s*"([a-z_]+)"', source))
        self.assertGreater(len(keys), 30)
        for locale, entries in self.tables.items():
            for key in keys:
                self.assertIn("group_" + key, entries, (locale, key))
        hant_overrides = json.loads(DATA_PATH.with_name("zh-Hant-overrides.json").read_text())
        for key, entry in self.tables["zh-Hant"].items():
            if key.startswith("group_error_"):
                self.assertEqual(hant_overrides[key]["value"], entry.value, key)

    def test_current_backend_business_errors_all_have_an_ios_mapping(self):
        server = ROOT.parent / "jifenqi-backend/api-server/src"
        if not server.exists():
            self.skipTest("Backend sibling checkout is not available")
        paths = list((server / "lib/groups").rglob("*.ts")) + [server / "routes/groups.ts"]
        codes = set()
        for path in paths:
            if re.search(r"(test|spec)", path.name):
                continue
            for expression in re.findall(r"new GroupError\(\s*[^,]+,\s*([^,]+),", path.read_text()):
                codes.update(re.findall(r'''['"]([A-Z_]+)['"]''', expression))
        source = (ROOT / "jifen/Features/Groups/GroupErrorMessage.swift").read_text()
        mapped = set(re.findall(r'"([A-Z_]+)":', source))
        self.assertGreater(len(codes), 70)
        self.assertEqual(codes - mapped, set())
        for platform, path, pattern in [
            ("HarmonyOS", ROOT.parent / "jifen-hos/entry/src/main/ets/helpers/groupErrorText.ts", r"case '([A-Z_]+)'"),
            ("Android", ROOT.parent / "jifen-android/app/src/main/java/com/douhua/jifen/screen/group/GroupUi.kt", r'"([A-Z_]+)"'),
        ]:
            if not path.exists():
                continue
            peer_source = path.read_text()
            if platform == "Android":
                peer_source = peer_source.split("private fun codeRes", 1)[1].split("else -> null", 1)[0]
            peer_codes = set(re.findall(pattern, peer_source))
            if "GroupRepository.NEED_LOGIN" in peer_source:
                peer_codes.add("NEED_LOGIN")
            self.assertEqual(codes - peer_codes, set(), platform)


if __name__ == "__main__":
    unittest.main()
