#!/usr/bin/env python3
"""One-off catalog repair for the feedback_time rename + 42 new keys.

Purges orphan rows (days_ago/hours_ago/minutes_ago), seeds missing rows with
fresh source hashes, refreshes stale hashes, and backfills finals from already
promoted .lproj resources. New rows without an existing translation stay
status=machine so the reviewed gate keeps blocking them until authored.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "localization"))
import localize  # noqa: E402

ORPHANS = {
    ("Localizable", "days_ago"),
    ("Localizable", "hours_ago"),
    ("Localizable", "minutes_ago"),
}
ORPHAN_PLURAL_PREFIXES = ("days_ago.", "hours_ago.", "minutes_ago.")
CHANGED_INFO_KEYS = {"NSCameraUsageDescription"}


def parse_strings_values(path: Path):
    if not path.exists():
        return {}
    return {e.key: e.value for e in localize.parse_strings(path, "Localizable")}


def parse_dict_values(path: Path):
    """Flat map key -> {category: value} from a stringsdict plist (xml)."""
    if not path.exists():
        return {}
    import plistlib
    with open(path, "rb") as handle:
        data = plistlib.load(handle)
    out = {}
    for key, entry in data.items():
        items = entry.get("NSStringPluralRuleType") and entry.get("localizedStringFormat")
        variants = entry.get("NSStringFormatArgsType")
        cases = {}
        feats = entry.get("items", {}) if isinstance(entry.get("items"), dict) else {}
        out[key] = {"format": items, "cases": cases, "features": feats}
    return out


def dict_finals(path: Path):
    """Return {(key, category): value} for a promoted .stringsdict."""
    import plistlib
    if not path.exists():
        return {}
    with open(path, "rb") as handle:
        data = plistlib.load(handle)
    finals = {}
    for key, entry in data.items():
        rules = entry.get("rules", {})
        for category, rule in rules.items():
            value = rule.get("value")
            if isinstance(value, str):
                finals[(key, category)] = value
    return finals


def main(dry_run: bool) -> int:
    catalog_dir = ROOT / "scripts" / "localization" / "catalogs"
    summary = {}
    for catalog_file in sorted(catalog_dir.glob("*.jsonl")):
        locale = catalog_file.stem
        rows = [json.loads(line) for line in catalog_file.read_text(encoding="utf-8").splitlines() if line.strip()]
        catalog = {(r["table"], r["key"]): r for r in rows}
        removed = 0
        for identity in list(catalog):
            table, key = identity
            if (table, key) in ORPHANS or (table == "Plural" and key.startswith(ORPHAN_PLURAL_PREFIXES)):
                del catalog[identity]
                removed += 1

        entries = localize.source_entries(locale)
        expected = {e.identity: e for e in entries}
        seeded, refreshed, backfilled = 0, 0, 0
        is_promoted = (ROOT / "jifen" / "Resources" / f"{locale}.lproj").exists()
        strings_finals = parse_strings_values(ROOT / "jifen" / "Resources" / f"{locale}.lproj" / "Localizable.strings") if is_promoted else {}
        dict_map = dict_finals(ROOT / "jifen" / "Resources" / f"{locale}.lproj" / "Localizable.stringsdict") if is_promoted else {}
        info_finals = parse_strings_values(ROOT / "jifen" / "Resources" / f"{locale}.lproj" / "InfoPlist.strings") if is_promoted else {}

        for identity, entry in expected.items():
            row = catalog.get(identity)
            if row is None:
                row = {"table": entry.table, "key": entry.key, "source_hash": entry.source_hash,
                       "azure": None, "google_web": None, "google": None, "final": None,
                       "status": "machine", "flags": [], "note": "seeded after feedback_time rename / new keys",
                       "machine_provider": None, "issues": []}
                catalog[identity] = row
                seeded += 1
            elif row.get("source_hash") != entry.source_hash:
                row["source_hash"] = entry.source_hash
                if identity[0] == "InfoPlist" and identity[1] in CHANGED_INFO_KEYS:
                    row["status"] = "machine"
                    row["final"] = None
                refreshed += 1
            if row.get("final") is None and is_promoted:
                value = None
                if entry.table == "Localizable":
                    value = strings_finals.get(entry.key) or info_finals.get(entry.key)
                elif entry.table == "Plural":
                    base, _, cat = entry.key.rpartition(".")
                    value = dict_map.get((base, cat))
                if value is not None:
                    row["final"] = value
                    row["status"] = "reviewed"
                    row["note"] = "backfilled from promoted resource"
                    backfilled += 1

        # rows present in catalog but not expected keep their reviewed value only if
        # they still exist in source; everything orphaned was purged above.
        stale_extra = set(catalog) - set(expected)
        for identity in stale_extra:
            del catalog[identity]

        # stable order: follow source_entries order
        ordered = [catalog[e.identity] for e in entries if e.identity in catalog]
        summary[locale] = dict(removed=removed, seeded=seeded, refreshed=refreshed, backfilled=backfilled, extra=len(stale_extra))
        if not dry_run:
            text = "\n".join(json.dumps(r, ensure_ascii=False) for r in ordered) + "\n"
            localize.atomic_write(catalog_file, text)
    widths = max(len(k) for k in summary)
    total = {k: 0 for k in ("removed", "seeded", "refreshed", "backfilled", "extra")}
    for loc, s in summary.items():
        if any(s.values()):
            print(f"{loc:>{widths}}  removed={s['removed']} seeded={s['seeded']} refreshed={s['refreshed']} backfilled={s['backfilled']} extra_dropped={s['extra']}")
        for k in total:
            total[k] += s[k]
    print("TOTAL", total, "(dry-run)" if dry_run else "(written)")
    return 0


if __name__ == "__main__":
    sys.exit(main("--apply" not in sys.argv))
