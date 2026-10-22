#!/usr/bin/env python3
"""Bring group headings and controls into the app's English Title Case.

The rest of the app titles headings, buttons and short field labels in Title
Case ("Recent Records", "Quick Start", "Saved Places", "Add Place", "Match
Details", "Sign Up"), while body copy, hints, notices, errors and empty states
stay in sentence case. The group feature was ported from Android, so its
headings and controls drifted into sentence case ("My groups", "Create group",
"Match rules"), which is the inconsistency reported on Home.

This script changes the **English source only**. Title Case is an English
typographic convention; German, French, Japanese and the other 43 locales keep
their existing reviewed native wording exactly as approved on 2026-10-21. Each
English edit re-hashes the matching catalog rows so the reviewed state stays
truthful, and both group review snapshots are refreshed.

Run with ``--check`` to verify nothing drifted; the default run writes.
"""
import argparse
import hashlib
import json
import plistlib
import re
from pathlib import Path

import localize

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "jifen/Resources"
CATALOGS = Path(__file__).with_name("catalogs")
DATA_PATH = Path(__file__).with_name("group-copy-20261017.json")
REVIEW_PATH = Path(__file__).with_name("group-copy-review-20261021.json")
SHARED_GROUP_KEYS = {"activity_direct_match_count", "archived_count"}
REVIEWED_ON = "2026-10-22"
REVIEWER = "Codex; no independent native-speaker review"
NOTE = ("Group English heading Title Case aligned with the rest of the app on "
        "2026-10-22; native translations unchanged; no external translation provider")

# Runtime key (without the `group_` prefix) -> reviewed Title Case English.
# Every entry below is a navigation title, section title, button/menu label,
# segment title, toggle label or short form-field label.
HEADINGS = {
    # Navigation titles
    "activity_detail": "Activity Details",
    "activity_lineup": "Arrange Matches",
    "activity_direct_title": "Arrange Now",
    "created": "Group Created",
    "create": "Create Group",
    "join": "Join Group",
    "match_rules": "Match Rules",
    "member_results_title": "Member Results",
    "my_groups": "My Groups",
    "archived_list_title": "Archived Groups",
    "activity_registration_manage": "Temporary Member Registration",
    "group_qr": "Group QR Code",
    "scan": "Scan QR Code",
    "cancel_schedule": "Cancel Schedule",
    "edit_schedule": "Edit Schedule",
    "leave_training": "Request Absence",
    "push_settings": "Notification Settings",
    "match_detail": "Match Details",
    # Section titles
    "training_schedule": "Training Schedule",
    "latest_results": "Latest Results",
    "regular_members": "Registered Members",
    "temporary_members": "Temporary Members",
    "removed_members": "Former Members",
    "leave_notices": "Student Leave Notices",
    "join_requests": "Join Requests",
    "overdue_tasks": "Overdue Tasks",
    "match_log": "Match History",
    "activity_section_past": "Past Activities",
    "activity_section_upcoming": "In Progress \u00b7 Registration Open",
    "pending_confirmation": "Awaiting Confirmation",
    # Buttons and menu actions
    "create_activity": "Create Activity",
    "manual_result": "Add Match Result",
    "start_score": "Start Scoring",
    "confirm_result": "Confirm Result",
    "audit_ui_share_number": "Share Group Number",
    "cancel_activity": "Cancel Activity",
    "complete_activity": "End Activity",
    "open_group": "Open Group",
    "report": "Report Group",
    "repair_upload": "Correct Result",
    "reload_version": "Load Latest Version",
    "leave": "Leave Group",
    "dissolve": "Dissolve Group",
    "cancel_dissolve": "Cancel Dissolution",
    "activity_direct_save": "Save Schedule",
    "apply_shift": "Apply Changes",
    "add_session": "Add Session",
    "add_temporary": "Add Temporary Member",
    "add_set": "Add Game",
    "shift_following": "Shift This and Following Matches",
    "audit_ui_share_qr": "Share QR Code",
    "audit_ui_share_invitation": "Share Invitation",
    "mark_seen": "Mark as Read",
    "notice_mark_all": "Mark All Read",
    "all_formats": "All Formats",
    "clear_seat": "Clear This Seat",
    "register": "Sign Up",
    "unregister": "Cancel Registration",
    "existing_result": "View Cloud Result",
    "set_admin": "Make Admin",
    "set_member": "Remove Administrator",
    "rename_member_title": "Edit Member Name",
    "edit_profile": "Edit Info",
    "transfer": "Transfer Ownership",
    "edit_lineup": "Arrange Matches",
    "sync": "Sync Now",
    "load_more": "Load More",
    "report_refresh": "Refresh Status",
    "report_remove_image": "Remove Image",
    "report_add_image": "Add Image",
    "report_supplement": "Add Information",
    # Form-field and toggle labels
    "join_policy": "Joining Options",
    "activity_field_title_optional": "Activity Name (Optional)",
    "activity_title": "Activity Name",
    "note": "Note (Optional)",
    "description": "Description (Optional)",
    "report_detail": "Details (Optional)",
    "name": "Group Name",
    "member_name": "Member Name",
    "completion_mode": "Match Completion",
    "rally_scoring": "Rally Scoring",
    "tennis_scoring": "Set Scoring",
    "games_per_set": "Games per Set",
    "win_by_two": "Win by Two",
    "no_ad": "No-Ad",
    "activity_lineup_duration": "Match Duration",
    "training_date": "Training Date",
    "starts_at": "Start Time",
    "registration_closes": "Registration Deadline",
    "push_enabled": "Group Notifications",
    "push_group_enabled": "Receive Notifications for This Group",
    "push_permission": "Enable System Notifications",
    "activity_reminder": "Remind Me 15 Minutes Before",
    "played_at": "Played At",
    "activity_my_registration": "My Registration",
    "activity_lineup_add": "Add Match",
    "activity_lineup_section_matches": "Match Schedule",
    "match_score": "Match Score",
    "overall_score": "Overall Set Score",
    "score_and_rules": "Score and Rules",
    "result_information": "Match Information",
    "set_details": "Set Details",
    "member_settings": "Member Settings",
    "settings": "Group Management",
    # Evidence-report sheet labels
    "report_evidence_title": "Image Evidence (Optional)",
    "report_preview": "Evidence Image",
}


def is_group_key(key):
    return key.startswith("group_") or key.split(".", 1)[0] in SHARED_GROUP_KEYS


def table(locale):
    return {entry.key: entry for entry in localize.parse_strings(
        RESOURCES / (locale + ".lproj/Localizable.strings"), "Localizable")}


def alias_targets():
    """Map every runtime key from the generated GroupCopyKey table."""
    source = (ROOT / "jifen/Features/Groups/GroupCopyKey.swift").read_text()
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', source))


def runtime_and_alias(prefix):
    key = "group_" + prefix
    mapping = alias_targets()
    target = mapping.get(key)
    return [key] if target is None or target == key else [key, target]


def plan_english(data):
    """Resolved English values plus the catalog rows each change touches."""
    english = {key: entry.value for key, entry in table("en").items()}
    touched = {}
    for prefix, value in HEADINGS.items():
        keys = runtime_and_alias(prefix)
        present = [key for key in keys if key in english]
        assert present, "Missing group key for %r" % prefix
        for key in present:
            touched[key] = value
    return english, touched


def rewritten_strings(text, edits):
    for key, value in edits.items():
        line = '"%s" = "%s";' % (key, localize.encode_apple_string(value))
        pattern = r'^"' + re.escape(key) + r'"\s*=.*;[ \t]*$'
        assert re.search(pattern, text, re.M), "Missing resource line for %s" % key
        text = re.sub(pattern, lambda _: line, text, flags=re.M)
    return text


def updated_reviewed_sources(data, english):
    sources = dict(data["reviewed_sources"])
    sources.update({key: value for key, value in english.items() if is_group_key(key)})
    return sources


def refreshed_catalog(locale, english):
    """Re-hash English-source changes; native wording and review status stay."""
    path = CATALOGS / (locale + ".jsonl")
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    changed = 0
    for row in rows:
        if row.get("table") != "Localizable" or not row.get("key", "").startswith("group_"):
            continue
        source = english.get(row["key"])
        if source is None:
            continue
        digest = hashlib.sha256(("Localizable\0" + row["key"] + "\0" + source).encode()).hexdigest()[:16]
        if row.get("source_hash") == digest:
            continue
        assert row.get("status") == "reviewed", (locale, row["key"])
        row["source_hash"] = digest
        row["note"] = NOTE
        changed += 1
    text = "\n".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) for row in rows) + "\n"
    return text, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    data = json.loads(DATA_PATH.read_text())
    english, edits = plan_english(data)
    changes = []

    en_path = RESOURCES / "en.lproj/Localizable.strings"
    en_text = rewritten_strings(en_path.read_text(), edits)
    if en_text != en_path.read_text():
        changes.append(str(en_path.relative_to(ROOT)))
        if not args.check:
            en_path.write_text(en_text)

    # The older group writer keeps an explicit English override table; a stale
    # entry would silently revert the heading it duplicates.
    current_overrides = data.get("overrides", {}).get("en", {})
    reworded = {key: value for key, value in edits.items() if key in current_overrides}
    expected_overrides = {**current_overrides, **reworded}
    expected_sources = updated_reviewed_sources(data, {**english, **edits})
    snapshot_stale = (data["reviewed_sources"] != expected_sources
                      or current_overrides != expected_overrides)
    if snapshot_stale:
        changes.append(str(DATA_PATH.relative_to(ROOT)))
        if not args.check:
            data["reviewed_sources"] = expected_sources
            if reworded:
                data.setdefault("overrides", {}).setdefault("en", {}).update(reworded)
            DATA_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n")

    merged = {**english, **edits}
    review = json.loads(REVIEW_PATH.read_text())
    stale = {key for key, value in review["sources"].items()
             if merged.get(key) != value}
    assert not stale - set(edits), "Review record references unrelated sources: %s" % sorted(stale - set(edits))
    # The English review table repeats each reviewed English source; leaving an
    # old sentence-case entry there would fail the explicit-review gate.
    english_review = review["locales"].get("en", {})
    stale_english = {key for key, value in english_review.items()
                     if key in edits and value != edits[key]}
    assert not stale_english - set(edits)
    if stale or stale_english:
        review["sources"].update({key: edits[key] for key in stale})
        review["locales"].setdefault("en", {}).update(
            {key: edits[key] for key in stale_english})
        review["reviewed_on"] = REVIEWED_ON
        review["reviewer"] = REVIEWER
        if isinstance(review.get("retained_wording"), str):
            review["retained_wording"] += (" English group headings moved to Title Case on "
                                           "2026-10-22; native wording retained.")
        else:
            review.setdefault("retained_wording", {}).update({key: edits[key] for key in stale})
        changes.append(str(REVIEW_PATH.relative_to(ROOT)))
        if not args.check:
            REVIEW_PATH.write_text(json.dumps(review, ensure_ascii=False, indent=1) + "\n")

    # A locale that legitimately renders the new English wording identically
    # must be recorded in the shared-terms whitelist, or the gate that blocks
    # untranslated group copy flags it.
    shared_terms = data.get("shared_terms", {})
    whitelist_stale = False
    native = {locale: table(locale) for locale in localize.locale_map()
              if locale not in {"en", "zh-Hans", "zh-Hant"}}
    for key, value in edits.items():
        matches = sorted(locale for locale, rows in native.items()
                         if key in rows and rows[key].value == value)
        if not matches:
            continue
        entry = shared_terms.setdefault(key, {"value": value, "locales": []})
        expected_locales = sorted(set(entry.get("locales", [])) | set(matches))
        if entry.get("value") != value or entry.get("locales") != expected_locales:
            whitelist_stale = True
            if not args.check:
                entry["value"] = value
                entry["locales"] = expected_locales
    if whitelist_stale:
        changes.append(str(DATA_PATH.relative_to(ROOT)))
        if not args.check:
            data["shared_terms"] = shared_terms
            DATA_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n")

    catalog_total = 0
    for locale in sorted(localize.locale_map()):
        path = CATALOGS / (locale + ".jsonl")
        if not path.exists():
            # English, Simplified and Traditional Chinese ship without a review
            # catalog; their resources are the reviewed source of truth.
            continue
        text, changed = refreshed_catalog(locale, merged)
        catalog_total += changed
        if text != path.read_text():
            changes.append(str(path.relative_to(ROOT)))
            if not args.check:
                path.write_text(text)

    if args.check and changes:
        raise SystemExit("Heading-case drift:\n" + "\n".join(changes))
    print("PASS: %d English headings across %d keys; %d catalog rows refreshed; %d files %s" % (
        len(HEADINGS), len(edits), catalog_total, len(changes),
        "need changes" if args.check else "updated"))


if __name__ == "__main__":
    main()
