#!/usr/bin/env python3
"""Strip the Google-web multi-alternative residue out of the Odia catalog.

Measured on 2026-09-29: 1,306 of 1,499 `or` rows carry a stray "|". 1,194 of them are a
single trailing pipe (pure scraping artifact); the remaining 112 hold several candidates
inside one sentence, sometimes with Latin fragments spliced mid-word, and are left
untouched so `validate_locale` flags them as `provider-artifact` for hand rewriting.

Both layers get repaired, because the provider cache is what seeds a catalog row again
after an English source string changes:
  * scripts/localization/catalogs/or.jsonl      (durable review state)
  * build/localization/cache/google-web/or.json (cache key = "Table:key:source_hash")

Dry run by default; pass --apply to write.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "localization" / "localize.py"

SPEC = importlib.util.spec_from_file_location("jifen_localize", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
localize = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = localize
SPEC.loader.exec_module(localize)

TRAILING_PIPE = re.compile(r"\s*\|\s*$")
LOCALE = "or"


def repair(value: str) -> tuple[str, bool]:
    if value.count("|") != 1:
        return value, False
    cleaned = TRAILING_PIPE.sub("", value)
    if not cleaned.strip() or "|" in cleaned:
        return value, False
    return cleaned, cleaned != value


def main(apply: bool) -> int:
    catalog_file = localize.CATALOG_ROOT / (LOCALE + ".jsonl")
    rows = [json.loads(line) for line in catalog_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    catalog = {(row["table"], row["key"]): row for row in rows}
    assert len(catalog) == len(rows), "duplicate identities in %s" % catalog_file

    fixed = 0
    for row in catalog.values():
        for field in ("google_web", "azure", "google", "final"):
            value = row.get(field)
            if not isinstance(value, str):
                continue
            cleaned, changed = repair(value)
            if changed:
                row[field] = cleaned
                fixed += 1

    remaining = [
        (row["table"], row["key"])
        for row in catalog.values()
        for field in ("google_web", "final")
        if isinstance(row.get(field), str) and "|" in row[field]
    ]

    cache_file = localize.BUILD_ROOT / "cache" / "google-web" / (LOCALE + ".json")
    cache_fixed = 0
    if cache_file.exists():
        cache = json.loads(cache_file.read_text(encoding="utf-8"))
        for key, value in list(cache.items()):
            cleaned, changed = repair(value)
            if changed:
                cache[key] = cleaned
                cache_fixed += 1
        if apply:
            localize.atomic_write(cache_file, json.dumps(cache, ensure_ascii=False, indent=2) + "\n")
    else:
        print("warning: provider cache missing at %s" % cache_file)

    print("%s: rows=%d values_stripped=%d cache_values_stripped=%d rows_still_piped=%d"
          % (LOCALE, len(catalog), fixed, cache_fixed, len(set(remaining))))
    for identity in sorted(set(remaining))[:5]:
        print("  hand-rewrite needed: %s/%s" % identity)

    if apply:
        ordered = [catalog[entry.identity] for entry in localize.source_entries(LOCALE) if entry.identity in catalog]
        assert len(ordered) == len(catalog), "source entries changed shape; refusing to drop rows"
        localize.atomic_write(catalog_file, "\n".join(json.dumps(row, ensure_ascii=False) for row in ordered) + "\n")
        report = localize.validate_locale(LOCALE, require_reviewed=False)
        codes: dict[str, int] = {}
        for blocker in report["blockers"]:
            codes[blocker["code"]] = codes.get(blocker["code"], 0) + 1
        print("validate: blockers=%d %s warnings=%d" % (len(report["blockers"]), codes, len(report["warnings"])))
        print("wrote %s" % catalog_file)
    else:
        print("dry run; pass --apply to write")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write the repaired catalog and cache")
    raise SystemExit(main(parser.parse_args().apply))
