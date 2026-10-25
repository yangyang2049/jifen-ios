#!/usr/bin/env python3
"""Export reviewed voice phrase catalogs to the three sibling mobile projects.

Runtime builders gate these tables by sport, language and phase; a translated
catalog row alone never enables a professional call. See the dated source audit.
"""
import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import voice_localization

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = Path(__file__).resolve().parent / "voice_catalogs"
LANGUAGES = {"ZH": "zh-Hans", "EN": "en", "JA": "ja", "KO": "ko", "FR": "fr", "ES": "es-ES", "PT": "pt-PT"}


def phrases(locale):
    catalog = json.loads((CATALOGS / f"{locale}.json").read_text())
    entries = catalog["entries"]
    errors = voice_localization.validate(locale, voice_localization.source_table(locale), entries)
    if catalog.get("locale") != locale:
        errors.append("catalog locale differs")
    if errors:
        raise ValueError(f"Refusing to export {locale}: " + "; ".join(errors))
    return {key: row["value"] for key, row in sorted(entries.items())}


def kotlin_string(value):
    return json.dumps(value, ensure_ascii=False).replace("$", "\\$")


def scoped_kotlin_catalog(existing, tables, prefixes):
    """Replace selected keys without regenerating a host's other language rows."""
    result, active, seen = [], None, set()
    for line in existing.splitlines(keepends=True):
        function = re.search(r"private fun ([a-z]+)\(\): Map<String, String> = mapOf\(", line)
        if function:
            active = function.group(1).upper()
            seen.add(active)
        elif active and line.strip() == ")":
            result.extend(f"        {kotlin_string(key)} to {kotlin_string(value)},\n"
                          for key, value in sorted(tables[active].items()) if key.startswith(tuple(prefixes)))
            active = None
        elif active:
            pair = re.match(r'\s*("(?:[^"\\]|\\.)*") to ', line)
            if pair and json.loads(pair.group(1).replace("\\$", "$")).startswith(tuple(prefixes)):
                continue
        result.append(line)
    if seen != set(tables):
        raise ValueError("Scoped catalog language inventory differs")
    return "".join(result)


def scoped_phrase_tables(existing, generated, prefixes):
    result = {language: dict(rows) for language, rows in existing.items()}
    for language, rows in generated.items():
        for key, value in rows.items():
            if key.startswith(tuple(prefixes)):
                result.setdefault(language, {})[key] = value
    return result


def merge_scoped_fixtures(existing, generated, sports, languages):
    """Refresh selected calls while preserving each host's other reviewed baselines."""
    def identity(row):
        return json.dumps({key: value for key, value in row.items() if key != "expected"}, sort_keys=True)
    calls = {identity(row): row for row in generated}
    result = []
    for row in existing:
        updated = dict(row, expected=dict(row["expected"]))
        if not sports or row["gameType"] in sports:
            replacement = calls.get(identity(row))
            if replacement is None:
                raise ValueError("Scoped fixture has no generated counterpart: " + identity(row))
            for language, value in replacement["expected"].items():
                if not languages or language in languages:
                    updated["expected"][language] = value
        result.append(updated)
    return result


def export_fixtures(sports=None, languages=None):
    test = ROOT / "Packages/JifenCore/Tests/JifenCoreTests/CrossPlatformVoiceExportTests.swift"
    if test.exists():
        raise RuntimeError(f"Refusing to overwrite {test}")
    with tempfile.TemporaryDirectory(prefix="reviewed-voice-fixtures-") as temp:
        output = Path(temp) / "fixtures.json"
        test.write_text((Path(__file__).parent / "fixtures/ReviewedVoiceFixtureExport.swift").read_text())
        try:
            subprocess.run(["swift", "test", "--package-path", str(ROOT / "Packages/JifenCore"), "--filter", "exportReviewedVoiceParityFixtures"],
                           env=dict(os.environ, REVIEWED_VOICE_CATALOGS=str(CATALOGS), REVIEWED_VOICE_FIXTURE_OUTPUT=str(output)), check=True)
        finally:
            test.unlink()
        groups = {}
        for row in json.loads(output.read_text()):
            lang, expected = row.pop("language"), row.pop("expected")
            # Normal tennis points above 4 cannot be represented by Android's
            # displayed 40/45 payload. Keep valid points, tie-breaks and endings.
            if (row["gameType"] in ("tennis", "tennis_doubles", "padel") and row["phase"] == "score_change"
                    and not row["isTieBreak"] and max(row["leftScore"], row["rightScore"]) > 4):
                continue
            key = json.dumps(row, sort_keys=True)
            groups.setdefault(key, dict(row, expected={}))["expected"][lang] = expected
        defaults = {"leftName": "Alice", "rightName": "Bob", "leftSets": 0, "rightSets": 0, "currentSet": 1,
                    "serverSide": "left", "winnerSide": "left", "serviceOver": False, "isTieBreak": False,
                    "criticalPoint": "", "midGameInterval": False, "tennisDeuceMode": "advantage", "serverNumber": 0,
                    "breakCue": "time", "secondServer": False, "starPointReturnedAdvantages": 0,
                    "returnedToDeuce": False, "maxSets": 7, "sideChange": False}
        for project in ("jifen-android", "jifen-android-google", "jifen-hos"):
            rows = [{key: value for key, value in row.items() if key not in defaults or defaults[key] != value} for row in groups.values()]
            if project != "jifen-android-google":
                rows = [dict(row, expected={key: value for key, value in row["expected"].items() if key in ("ZH", "EN")}) for row in rows]
            relative = "scripts/fixtures/reviewed-ios-voice.json" if project == "jifen-hos" else "shared-core/src/test/resources/voice/reviewed-ios-fixtures.json"
            target = ROOT.parent / project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if sports or languages:
                if not target.is_file():
                    raise ValueError(f"Scoped fixture update requires an existing baseline: {target}")
                rows = merge_scoped_fixtures(json.loads(target.read_text()), rows, sports, languages)
            target.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
            print(f"Exported {len(rows)} scenarios / {sum(len(row['expected']) for row in rows)} calls to {project}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", action="store_true", help="Also export actual iOS production messages for parity tests")
    parser.add_argument("--fixture-sport", action="append", help="Update only this sport in existing fixture baselines (repeatable)")
    parser.add_argument("--fixture-language", action="append", help="Update only this language identity, e.g. ZH (repeatable)")
    parser.add_argument("--phrase-prefix", action="append", help="Update only matching template keys in existing host catalogs (repeatable)")
    args = parser.parse_args()
    if (args.fixture_sport or args.fixture_language) and not args.fixtures:
        parser.error("--fixture-sport and --fixture-language require --fixtures")
    # Preflight the complete source/resource gate before changing any sibling
    # project. Reviewed status alone does not protect against stale hashes,
    # missing parameters or a promoted table that has drifted from the catalog.
    if voice_localization.main(["validate"]) != 0:
        raise ValueError("Refusing to export sports voice catalogs with validation blockers")
    for project, languages in [("jifen-android", ["ZH", "EN"]), ("jifen-android-google", list(LANGUAGES))]:
        tables = {lang: phrases(LANGUAGES[lang]) for lang in languages}
        lines = ["// Generated by jifen-ios/scripts/localization/sync_reviewed_voice_catalogs.py.",
                 "package com.douhua.jifen.scoreboard.voice", "", "internal object ReviewedVoicePhrases {",
                 "    val tables: Map<String, Map<String, String>> = mapOf(" + ", ".join(f'\"{lang}\" to {lang.lower()}()' for lang in languages) + ")"]
        for lang in languages:
            lines.append(f"    private fun {lang.lower()}(): Map<String, String> = mapOf(")
            lines.extend(f"        {kotlin_string(key)} to {kotlin_string(value)}," for key, value in tables[lang].items())
            lines.append("    )")
        lines.append("}\n")
        target = ROOT.parent / project / "shared-core/src/main/java/com/douhua/jifen/scoreboard/voice/ReviewedVoicePhrases.kt"
        output = scoped_kotlin_catalog(target.read_text(), tables, args.phrase_prefix) if args.phrase_prefix else "\n".join(lines)
        target.write_text(output)
        print(f"Exported {target}")
    target = ROOT.parent / "jifen-hos/entry/src/main/ets/media/reviewedVoicePhrases.ts"
    tables = {"zh-CN": phrases("zh-Hans"), "en-US": phrases("en")}
    if args.phrase_prefix:
        existing = json.loads(target.read_text().split("=", 1)[1].strip().removesuffix(";"))
        tables = scoped_phrase_tables(existing, tables, args.phrase_prefix)
    target.write_text("// Generated by jifen-ios/scripts/localization/sync_reviewed_voice_catalogs.py.\n"
                      + "export const reviewedVoicePhrases: Record<string, Record<string, string>> = "
                      + json.dumps(tables, ensure_ascii=False, indent=2) + ";\n")
    print(f"Exported {target}")
    if args.fixtures:
        export_fixtures(set(args.fixture_sport or []), set(args.fixture_language or []))


if __name__ == "__main__":
    main()
