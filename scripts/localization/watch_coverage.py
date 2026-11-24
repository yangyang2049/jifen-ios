#!/usr/bin/env python3
"""Report localization coverage for the Apple Watch app.

The watch ships its own string catalog (jifenWatch Watch App/Resources). Until a
locale is reviewed and added there, iOS falls back to English per key. This
script answers two questions for every phone locale:

1. How many watch keys already have a phone translation with the same key?
2. Which watch-only keys still need a reviewed translation?

Usage:
    python3 scripts/localization/watch_coverage.py            # table
    python3 scripts/localization/watch_coverage.py --json      # machine output
    python3 scripts/localization/watch_coverage.py --missing ja
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
from typing import Dict, Set

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WATCH_RES = os.path.join(ROOT, "jifenWatch Watch App", "Resources")
PHONE_RES = os.path.join(ROOT, "jifen", "Resources")
ENTRY_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=')


def keys(path: str) -> Set[str]:
    out: Set[str] = set()
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = ENTRY_RE.match(line)
            if match:
                out.add(match.group(1))
    return out


def locales(res: str) -> Dict[str, str]:
    found = {}
    for path in sorted(glob.glob(os.path.join(res, "*.lproj", "Localizable.strings"))):
        found[os.path.basename(os.path.dirname(path))] = path
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--missing", help="print watch-only keys missing for this locale")
    args = parser.parse_args()

    watch_en = keys(os.path.join(WATCH_RES, "en.lproj", "Localizable.strings"))
    phone_locales = locales(PHONE_RES)
    watch_locales = set(locales(WATCH_RES))

    report = {
        "watchKeys": len(watch_en),
        "shippedLocales": sorted(watch_locales),
        "phoneLocales": len(phone_locales),
        "locales": [],
    }
    for locale, path in phone_locales.items():
        phone_keys = keys(path)
        reusable = watch_en & phone_keys
        report["locales"].append({
            "locale": locale,
            "reusable": len(reusable),
            "coverage": round(100 * len(reusable) / max(1, len(watch_en)), 1),
            "shipped": locale in watch_locales,
        })

    if args.missing:
        path = phone_locales.get(args.missing)
        if not path:
            print(f"unknown locale: {args.missing}")
            return 1
        for key in sorted(watch_en - keys(path)):
            print(key)
        return 0

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0

    print(f"watch keys: {report['watchKeys']}")
    print(f"watch locales: {', '.join(report['shippedLocales'])}")
    print(f"phone locales: {report['phoneLocales']}")
    print()
    print(f"{'locale':10} {'reusable':>9} {'coverage':>9}  shipped")
    for row in report["locales"]:
        print(f"{row['locale']:10} {row['reusable']:9} {row['coverage']:8}%  {'yes' if row['shipped'] else 'no'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
