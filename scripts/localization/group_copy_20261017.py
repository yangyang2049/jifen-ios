#!/usr/bin/env python3
"""Apply and audit the Codex-authored group copy across all 47 app locales.

No translation provider is called. The data file contains complete sentences;
aliases reuse established app terminology, never word-by-word translation.
Only group resources/catalog rows are changed. Run with --check for a read-only
check that resources and review catalogs still agree with the authored copy.
"""
import argparse
import hashlib
import json
import plistlib
import re
import unicodedata
from pathlib import Path

import localize

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "jifen/Resources"
DATA_PATH = Path(__file__).with_name("group-copy-20261017.json")
SHARED_GROUP_KEYS = {"activity_direct_match_count", "archived_count"}


def is_group_key(key):
    return key.startswith("group_") or key.split(".", 1)[0] in SHARED_GROUP_KEYS


def table(locale):
    return {entry.key: entry for entry in localize.parse_strings(
        RESOURCES / (locale + ".lproj/Localizable.strings"), "Localizable")}


def require_reviewed_sources(data):
    # A fresh source hash alone is not evidence that a translation was reviewed.
    # Keep the exact English snapshot in the authored pack and fail before any
    # writes when source copy changes, including newly added canonical aliases.
    english_sources = {key: entry.value for key, entry in table("en").items() if is_group_key(key)}
    assert data.get("reviewed_sources") == english_sources, "Group source changed after copy review; review translations before updating the source snapshot"


def planned_tables(data):
    require_reviewed_sources(data)
    locales = {p.stem for p in RESOURCES.glob("*.lproj")}
    assert locales == set(data["locales"]), "Every shipped locale needs explicit copy"
    keys = data["keys"]
    assert len(keys) == len(set(keys)), "Duplicate authored key"
    result = {}
    for locale in sorted(locales):
        original = table(locale)
        values = data["locales"][locale]
        assert len(keys) == len(values), (locale, "incomplete authored copy")
        authored = dict(zip(keys, values))
        # Preserve existing English and Chinese copy; only add the error messages.
        if locale in {"en", "zh-Hans", "zh-Hant"}:
            authored = {key: value for key, value in authored.items()
                        if key.startswith("group_error_")}
        else:
            for key, source_key in data["aliases"].items():
                authored[key] = authored.get(source_key, original[source_key].value)
        authored.update(data.get("overrides", {}).get(locale, {}))
        plurals = data["plurals"][locale]
        assert plurals.keys() == SHARED_GROUP_KEYS, (locale, "shared counters missing")
        for key, forms in plurals.items():
            assert set(forms) == set(localize.locale_map()[locale]["plural_categories"]), (locale, key)
            for value in forms.values():
                assert localize.format_arguments(value) == localize.format_arguments("%d"), (locale, key)
                assert unicodedata.normalize("NFC", value) == value, (locale, key)
            authored[key] = forms["other"]
        merged = {key: entry.value for key, entry in original.items()}
        merged.update(authored)
        result[locale] = (authored, merged)
    english = result["en"][1]
    for locale, (_, merged) in result.items():
        assert merged.keys() == english.keys(), (locale, "resource keys differ")
        for key, value in merged.items():
            if not is_group_key(key):
                continue
            assert value, (locale, key, "empty copy")
            assert unicodedata.normalize("NFC", value) == value, (locale, key, "non-NFC copy")
            assert localize.format_arguments(value) == localize.format_arguments(english[key]), (locale, key, "format arguments differ")
            assert value.count("\n") == english[key].count("\n"), (locale, key, "newlines differ")
    return result


def update_resource(path, authored):
    text = path.read_text()
    for key, value in authored.items():
        line = '"%s" = "%s";' % (key, localize.encode_apple_string(value))
        pattern = r'^"' + re.escape(key) + r'"\s*=.*;[ \t]*$'
        if re.search(pattern, text, re.M):
            text = re.sub(pattern, lambda _: line, text, flags=re.M)
        else:
            text = text.rstrip("\n") + "\n" + line + "\n"
    return text


def catalog_text(locale, merged, plurals):
    path = ROOT / "scripts/localization/catalogs" / (locale + ".jsonl")
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    by_key = {(row["table"], row["key"]): row for row in rows}
    english = table("en")
    def upsert(table_name, key, value, digest):
        row = by_key.get((table_name, key))
        if row and row.get("source_hash") == digest and row.get("final") == value and row.get("status") == "reviewed" and not row.get("flags") and not row.get("issues"):
            return
        if row is None:
            row = dict(table=table_name, key=key, azure=None, google_web=None,
                       google=None, machine_provider=None)
            rows.append(row)
        row.update(source_hash=digest, final=value, status="reviewed", flags=[], issues=[],
                   note="Group source and native copy reviewed by Codex 2026-10-21; exact source snapshot in group-copy-20261017.json; no external translation provider")
    for key, value in merged.items():
        if is_group_key(key):
            digest = hashlib.sha256(("Localizable\0" + key + "\0" + english[key].value).encode()).hexdigest()[:16]
            upsert("Localizable", key, value, digest)
    for entry in localize.plural_entries(locale):
        if is_group_key(entry.key):
            key, category = entry.key.rsplit(".", 1)
            upsert("Plural", entry.key, plurals[key][category], entry.source_hash)
    return path, "\n".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) for row in rows) + "\n"


def plural_resource(path, plurals):
    payload = plistlib.loads(path.read_bytes())
    for key, forms in plurals.items():
        payload[key] = {
            "NSStringLocalizedFormatKey": "%#@count@",
            "count": {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
                      "NSStringFormatValueTypeKey": "d", **forms},
        }
    return plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = json.loads(DATA_PATH.read_text())
    plans = planned_tables(data)
    changes = []
    # The English table must be saved before computing catalog source hashes.
    for locale in ["en"] + sorted(set(plans) - {"en"}):
        authored, merged = plans[locale]
        path = RESOURCES / (locale + ".lproj/Localizable.strings")
        text = update_resource(path, authored)
        if text != path.read_text():
            changes.append(str(path.relative_to(ROOT)))
            if not args.check:
                path.write_text(text)
        plural_path = path.with_suffix(".stringsdict")
        plural_bytes = plural_resource(plural_path, data["plurals"][locale])
        if plural_bytes != plural_path.read_bytes():
            changes.append(str(plural_path.relative_to(ROOT)))
            if not args.check:
                plural_path.write_bytes(plural_bytes)
    if args.check and changes:
        raise SystemExit("Authored resource drift:\n" + "\n".join(changes))
    for locale, (_, merged) in plans.items():
        if locale in {"en", "zh-Hans", "zh-Hant"}:
            continue
        path, text = catalog_text(locale, merged, data["plurals"][locale])
        if text != path.read_text():
            changes.append(str(path.relative_to(ROOT)))
            if not args.check:
                path.write_text(text)
    if args.check and changes:
        raise SystemExit("Catalog drift:\n" + "\n".join(changes))
    count = sum(key.startswith("group_") for key in plans["en"][1])
    print("PASS: %d locales × %d group keys + 2 shared counters; formats, plurals and catalog parity; %d files %s" % (
        len(plans), count, len(changes), "need changes" if args.check else "updated"))


if __name__ == "__main__":
    main()
