#!/usr/bin/env python3
"""Check the Apple Watch resource tables against the phone's supported locales."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from localize import format_arguments, locale_map, parse_strings

ROOT = Path(__file__).resolve().parents[2]
WATCH_APP = ROOT / "jifenWatch Watch App"
WATCH_RES = WATCH_APP / "Resources"
PHONE_RES = ROOT / "jifen" / "Resources"
SHARED_STRINGS = Path(__file__).with_name("watch_shared_strings.json")

STRING_LOOKUP = re.compile(r'\bNSLocalizedString\(\s*"([^"\\]+)"')


def table_entries(path: Path) -> dict[str, str]:
    return {entry.key: entry.value for entry in parse_strings(path, path.stem)} if path.is_file() else {}


def language_files(resources: Path, filename: str) -> dict[str, Path]:
    return {path.parent.stem: path for path in sorted(resources.glob(f"*.lproj/{filename}"))}


def resource_tables(locales: list[str]) -> dict[str, dict[str, dict[str, str]]]:
    tables = {}
    for source in sorted((WATCH_RES / "en.lproj").glob("*.strings")):
        paths = language_files(WATCH_RES, source.name)
        tables[source.stem] = {locale: table_entries(paths[locale]) if locale in paths else {}
                               for locale in locales}
    for path in sorted(WATCH_RES.glob("*.xcstrings")):
        catalog = json.loads(path.read_text(encoding="utf-8"))
        tables[path.stem] = {locale: {} for locale in locales}
        for key, item in catalog["strings"].items():
            for locale, localization in item.get("localizations", {}).items():
                if locale in tables[path.stem]:
                    tables[path.stem][locale][key] = localization.get("stringUnit", {}).get("value", "")
    return tables


def coverage() -> dict:
    phone_files = language_files(PHONE_RES, "Localizable.strings")
    watch_files = language_files(WATCH_RES, "Localizable.strings")
    locales = sorted(locale_map())
    expected_locales = set(locales)
    locale_differences = {
        target: {
            "missing": sorted(expected_locales - files.keys()),
            "extra": sorted(files.keys() - expected_locales),
        }
        for target, files in (("phone", phone_files), ("watch", watch_files))
    }
    tables = resource_tables(locales)
    pairs = json.loads(SHARED_STRINGS.read_text(encoding="utf-8"))
    missing_source = set()
    source_keys = {key for name, table in tables.items() if name != "InfoPlist" for key in table["en"]}
    for file in WATCH_APP.rglob("*.swift"):
        missing_source.update(set(STRING_LOOKUP.findall(file.read_text(encoding="utf-8"))) - source_keys)

    rows = []
    for locale in locales:
        missing, extra, invalid_formats, shared_mismatches = [], [], [], []
        phone = table_entries(phone_files[locale]) if locale in phone_files else {}
        for name, table in tables.items():
            english, translated = table["en"], table[locale]
            for key, value in english.items():
                item = f"{name}/{key}"
                translation = translated.get(key, "")
                if not translation.strip():
                    missing.append(item)
                else:
                    arguments = format_arguments(translation)
                    if arguments != format_arguments(value) or arguments[1]:
                        invalid_formats.append(item)
            extra.extend(f"{name}/{key}" for key in translated.keys() - english.keys())
        for name, shared in pairs.items():
            for watch_key, phone_key in shared.items():
                value = tables[name][locale].get(watch_key)
                if not value or value != phone.get(phone_key):
                    shared_mismatches.append(f"{name}/{watch_key} ↔ {phone_key}")
        rows.append({
            "locale": locale,
            "missing": missing,
            "extra": sorted(extra),
            "invalidFormats": invalid_formats,
            "sharedMismatches": shared_mismatches,
        })
    return {
        "watchKeys": sum(len(table["en"]) for table in tables.values()),
        "phoneLocales": len(phone_files),
        "localeDifferences": locale_differences,
        "missingSourceKeys": sorted(missing_source),
        "locales": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print the complete machine-readable audit")
    parser.add_argument("--missing", help="print missing watch table entries for a locale")
    parser.add_argument("--check", action="store_true", help="fail on coverage, format or shared-translation differences")
    args = parser.parse_args()
    report = coverage()
    rows = report["locales"]
    if args.missing:
        locale = args.missing.removesuffix(".lproj")
        row = next((row for row in rows if row["locale"] == locale), None)
        if row is None:
            parser.error(f"unknown locale: {args.missing}")
        print("\n".join(row["missing"]))
    elif args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(f"{report['watchKeys']} watch entries across {report['phoneLocales']} language and region variants")
        for target, differences in report["localeDifferences"].items():
            for kind, locales in differences.items():
                if locales:
                    print(f"{target} {kind} locales: {', '.join(locales)}")
        for row in rows:
            if row["missing"] or row["extra"] or row["invalidFormats"] or row["sharedMismatches"]:
                print(f"{row['locale']:7} {len(row['missing']):3} missing  "
                      f"{len(row['extra']):3} extra  {len(row['invalidFormats']):3} format mismatches  "
                      f"{len(row['sharedMismatches']):3} phone/watch differences")
                for key in row["extra"] + row["invalidFormats"] + row["sharedMismatches"]:
                    print(f"  {key}")
        if report["missingSourceKeys"]:
            print("Missing from English: " + ", ".join(report["missingSourceKeys"]))
    incomplete = report["missingSourceKeys"] or any(
        locales for differences in report["localeDifferences"].values() for locales in differences.values()
    ) or any(
        row["missing"] or row["extra"] or row["invalidFormats"] or row["sharedMismatches"] for row in rows
    )
    return int(args.check and bool(incomplete))


if __name__ == "__main__":
    raise SystemExit(main())
