#!/usr/bin/env python3
"""Author the 42 Localizable rows that carry no provider draft in the 30 machine-draft catalogs.

`review-packet` only emits rows whose `machine_candidate(row)` is non-empty, so these rows
never reach a review packet and stay `empty` blockers forever. This script turns
`new-keys-30locales-2026-09-29.json` into official `apply-review` decision files.

Dry run by default; pass --apply to run `localize.py apply-review` for each locale listed.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "localization" / "localize.py"
DATA = Path(__file__).with_name("new-keys-30locales-2026-09-29.json")

SPEC = importlib.util.spec_from_file_location("jifen_localize", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
localize = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = localize
SPEC.loader.exec_module(localize)


def format_signature(value: str):
    arguments, mixed = localize.format_arguments(value)
    return (tuple(sorted(arguments.items())), mixed)


def main(apply: bool, only: list[str]) -> int:
    payload = json.loads(DATA.read_text(encoding="utf-8"))
    source = localize.source_by_identity("en")
    report_dir = localize.BUILD_ROOT / "review" / "empty-rows"
    totals = {}
    for locale, values in sorted(payload.items()):
        if locale.startswith("_") or not isinstance(values, dict):
            continue
        if only and locale not in only:
            continue
        catalog = localize.load_catalog(locale)
        lines, problems = [], []
        for key, value in values.items():
            identity = ("Localizable", key)
            entry = source.get(identity)
            row = catalog.get(identity)
            if entry is None or row is None:
                problems.append("%s: unknown identity" % key)
                continue
            if localize.machine_candidate(row) or row.get("status") in localize.REVIEW_STATES:
                problems.append("%s: row already has a draft or is reviewed" % key)
                continue
            if format_signature(entry.value) != format_signature(value):
                problems.append("%s: placeholder mismatch %r != %r" % (key, entry.value, value))
                continue
            if "|" in value:
                problems.append("%s: pipe residue" % key)
                continue
            lines.append(json.dumps({
                "table": "Localizable",
                "key": key,
                "decision": "revise",
                "value": value,
                "note": "hand-authored, no provider draft",
                "issues": ["missing-draft"],
            }, ensure_ascii=False))
        if problems:
            print("%s: REFUSED" % locale)
            for problem in problems:
                print("   %s" % problem)
            return 1
        path = report_dir / ("%s-42rows.jsonl" % locale)
        text = "\n".join(lines) + "\n"
        if apply:
            localize.atomic_write(path, text)
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "apply-review", "--locale", locale, "--input", str(path)],
                capture_output=True, text=True, check=False, cwd=ROOT,
            )
            if result.returncode != 0:
                print("%s: apply-review failed\n%s%s" % (locale, result.stdout, result.stderr))
                return 1
            print("%s: %s" % (locale, result.stdout.strip().splitlines()[-1]))
        else:
            print("%s: %d rows prepared, 0 problems" % (locale, len(lines)))
        totals[locale] = len(lines)
    print("locales=%d rows=%d %s" % (len(totals), sum(totals.values()), "applied" if apply else "dry run"))
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--locale", action="append", default=[], dest="only")
    args = parser.parse_args()
    raise SystemExit(main(args.apply, args.only))
