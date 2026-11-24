#!/usr/bin/env python3
"""Export the watch catalog for the translation pipeline.

Writes a JSON hand-off (key, English source, placeholders, and the phone key
that already carries a reviewed translation when one exists) so the localization
campaign can translate the watch-only keys without re-keying the source.

Usage:
    python3 scripts/localization/export_watch_keys.py            # build/localization/watch-keys.json
    python3 scripts/localization/export_watch_keys.py --out path
"""
from __future__ import annotations

import argparse
import json
import os
import re
from typing import Dict, List

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WATCH_EN = os.path.join(ROOT, "jifenWatch Watch App", "Resources", "en.lproj", "Localizable.strings")
PHONE_EN = os.path.join(ROOT, "jifen", "Resources", "en.lproj", "Localizable.strings")
DEFAULT_OUT = os.path.join(ROOT, "build", "localization", "watch-keys.json")
ENTRY_RE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$')
PLACEHOLDER_RE = re.compile(r'%(?:\d+\$)?[@dfs]|%%')


def entries(path: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = ENTRY_RE.match(line.strip())
            if match:
                out[match.group(1)] = match.group(2)
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    watch = entries(WATCH_EN)
    phone = entries(PHONE_EN)

    rows: List[dict] = []
    for key, source in watch.items():
        rows.append({
            "key": key,
            "source": source,
            "placeholders": PLACEHOLDER_RE.findall(source),
            "phoneKey": key if key in phone else None,
            "status": "reusable" if key in phone else "needs-translation",
        })

    needs = [row for row in rows if row["status"] == "needs-translation"]
    payload = {
        "source": os.path.relpath(WATCH_EN, ROOT),
        "totalKeys": len(rows),
        "reusableFromPhone": len(rows) - len(needs),
        "needsTranslation": len(needs),
        "keys": rows,
    }

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"wrote {args.out}: {payload['totalKeys']} keys, "
          f"{payload['reusableFromPhone']} reusable, {payload['needsTranslation']} to translate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
