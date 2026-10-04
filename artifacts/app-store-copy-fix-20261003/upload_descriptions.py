#!/usr/bin/env python3
"""Plan or PATCH only the eight reviewed App Store 3.3 descriptions.

Default is a read-only live plan. --apply is an explicit write opt-in.
Never creates localizations, uploads screenshots, changes other metadata,
submits a review, or releases a version. Credentials and JWTs stay in memory.
"""
import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from app_store_screenshots import API, APIError, save

APP_ID = "6759768784"
BUNDLE_ID = "com.douhua.jifen.ios"
VERSION = "3.3"
VERSION_ID = "a118dc62-4303-4c03-ae92-b358c60438d5"
INFO_ID = "1aa0ff31-d3d8-4d53-8b4e-983263bf8659"
ALLOWED_LOCALES = {"da", "fr-CA", "fr-FR", "id", "ms", "th", "ur-PK", "vi"}
DRAFT_STATE = "PREPARE_FOR_SUBMISSION"
URLS = ["https://jifenqi.com/terms", "https://jifenqi.com/privacy",
        "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"]


class DescriptionAPI(API):
    """Reject every remote mutation except exact description-only PATCHes."""
    def __init__(self, *args):
        super().__init__(*args)
        self.allowed_localization_ids = set()

    def request(self, method, path, body=None):
        if method != "GET":
            prefix = "/appStoreVersionLocalizations/"
            if method != "PATCH" or not path.startswith(prefix):
                raise RuntimeError("Only description PATCH is permitted")
            identifier = path[len(prefix):]
            data = (body or {}).get("data", {})
            attrs = data.get("attributes", {})
            if (identifier not in self.allowed_localization_ids or
                    data.get("type") != "appStoreVersionLocalizations" or
                    data.get("id") != identifier or set(attrs) != {"description"} or
                    set(data) != {"type", "id", "attributes"} or
                    set(body) != {"data"}):
                raise RuntimeError("Refusing a mutation outside the description allowlist")
        return super().request(method, path, body)


def map_localizations(resources):
    result = {}
    for resource in resources:
        code = resource["attributes"]["locale"]
        if code in result:
            raise RuntimeError("Duplicate localization identity: " + code)
        result[code] = resource
    return result


def desired_descriptions(directory, selected):
    result = {}
    for code in selected:
        resource = json.loads((directory / (code + ".json")).read_text())
        value = resource["description"]
        if resource.get("locale") != code:
            raise RuntimeError("Local file locale identity mismatch: " + code)
        if not value or len(value.encode("utf-16-le")) // 2 > 4000:
            raise RuntimeError("Description length is invalid: " + code)
        if re.findall(r"https?://[^\s]+", value) != URLS:
            raise RuntimeError("Description must retain all three complete URLs: " + code)
        if not all(url in value.splitlines() for url in URLS):
            raise RuntimeError("Each URL must occupy its own line: " + code)
        if len(value.split("\n\n")) != 7 or "\\n" in value or "\r" in value or "\t" in value:
            raise RuntimeError("Description paragraph/control-character check failed: " + code)
        result[code] = value
    return result


def validate_reviewed_updates(changes_file, originals, desired):
    """Bind each desired description to both the audit and original JSON backup."""
    changes = json.loads(changes_file.read_text())
    if (changes.get("platform"), changes.get("version"), changes.get("appId"),
            changes.get("versionId")) != ("IOS", VERSION, APP_ID, VERSION_ID):
        raise RuntimeError("Reviewed metadata change target mismatch")
    updates = {}
    for row in changes["descriptionUpdates"]:
        code = row["locale"]
        if code in updates:
            raise RuntimeError("Duplicate reviewed description: " + code)
        updates[code] = row
    if set(updates) != ALLOWED_LOCALES:
        raise RuntimeError("Reviewed description update set differs from the eight-locale allowlist")
    backup_root = Path(changes["backupRoot"])
    for code, value in desired.items():
        if code not in originals:
            raise RuntimeError("Audit baseline lacks selected locale: " + code)
        old = originals[code]["attributes"].get("description")
        backup = json.loads((backup_root / "locales" / (code + ".json")).read_text())
        row = updates[code]
        if (backup.get("locale") != code or backup.get("description") != old or
                row.get("oldDescription") != old or row.get("description") != value):
            raise RuntimeError("Description differs from the reviewed changes or original backup: " + code)


def require_target(api):
    app = api.request("GET", "/apps/" + APP_ID)["data"]
    if app["id"] != APP_ID or app["attributes"].get("bundleId") != BUNDLE_ID:
        raise RuntimeError("Wrong app ID or bundle ID")
    matches = [resource for resource in api.list("/apps/" + APP_ID + "/appStoreVersions")
               if resource["attributes"].get("platform") == "IOS" and
               resource["attributes"].get("versionString") == VERSION]
    if len(matches) != 1 or matches[0]["id"] != VERSION_ID:
        raise RuntimeError("Expected exactly the recorded iOS 3.3 version")
    version = matches[0]
    if version["attributes"].get("appStoreState") != DRAFT_STATE:
        raise RuntimeError("Expected iOS 3.3 in PREPARE_FOR_SUBMISSION")
    infos = api.list("/apps/" + APP_ID + "/appInfos")
    info = next((resource for resource in infos if resource["id"] == INFO_ID), None)
    if not info or info["attributes"].get("appStoreState") != DRAFT_STATE:
        raise RuntimeError("Expected the recorded draft AppInfo")
    return app, version, info


def live_snapshot(api):
    app, version, info = require_target(api)
    return {
        "app": app, "appStoreVersion": version, "appInfo": info,
        "appStoreVersionLocalizations": api.list(
            "/appStoreVersions/" + VERSION_ID + "/appStoreVersionLocalizations"),
        "appInfoLocalizations": api.list(
            "/appInfos/" + INFO_ID + "/appInfoLocalizations"),
    }


def preservation_issues(before, after, applied):
    """Verify every visible metadata attribute; only applied descriptions vary."""
    issues = []
    for kind in ["app", "appInfo", "appStoreVersion"]:
        if (before[kind]["id"] != after[kind]["id"] or
                before[kind]["attributes"] != after[kind]["attributes"]):
            issues.append({"resource": kind, "reason": "resource identity or attributes changed"})
    for kind in ["appInfoLocalizations", "appStoreVersionLocalizations"]:
        prior, current = map_localizations(before[kind]), map_localizations(after[kind])
        if set(prior) != set(current):
            issues.append({"resource": kind, "reason": "localization set changed"})
        for code, resource in prior.items():
            actual = current.get(code)
            if not actual or actual["id"] != resource["id"]:
                issues.append({"resource": kind, "locale": code, "reason": "identity changed"})
                continue
            expected = dict(resource["attributes"])
            if kind == "appStoreVersionLocalizations" and code in applied:
                expected["description"] = applied[code]
            attrs = actual["attributes"]
            for field in sorted(set(expected) | set(attrs)):
                if (field not in expected or field not in attrs or
                        expected[field] != attrs[field]):
                    issues.append({"resource": kind, "locale": code, "field": field})
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credentials", type=Path, default=Path(
        "/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json"))
    parser.add_argument("--metadata-dir", type=Path, default=ROOT /
                        "marketing/app-store/localization-2026-10-02/locales")
    parser.add_argument("--baseline", type=Path, default=ROOT /
                        "artifacts/app-store-copy-audit-20261003/live-descriptions-before.json")
    parser.add_argument("--changes", type=Path, default=ROOT /
                        "artifacts/app-store-copy-fix-20261003/metadata-changes.json")
    parser.add_argument("--out-dir", type=Path, default=Path(__file__).parent / "description-upload")
    parser.add_argument("--locale", action="append", choices=sorted(ALLOWED_LOCALES))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    selected = sorted(set(args.locale or ALLOWED_LOCALES))
    desired = desired_descriptions(args.metadata_dir, selected)
    baseline = json.loads(args.baseline.read_text())
    if baseline.get("appId") != APP_ID or baseline.get("versionId") != VERSION_ID:
        raise RuntimeError("Audit baseline target mismatch")
    originals = map_localizations(baseline["localizations"])
    validate_reviewed_updates(args.changes, originals, desired)
    stored = json.loads((ROOT / "marketing/app-store/localization-2026-10-02/upload-state.json").read_text())
    if (stored.get("appId"), stored.get("version"), stored.get("appStoreVersionId"),
            stored.get("appInfoId")) != (APP_ID, VERSION, VERSION_ID, INFO_ID):
        raise RuntimeError("Recorded upload-state identity mismatch")
    config = json.loads(args.credentials.read_text())
    key_file = Path(config["privateKeyFile"]).expanduser()
    if not key_file.is_absolute():
        key_file = args.credentials.resolve().parent / key_file
    api = DescriptionAPI(key_file.resolve(), config["keyId"], config.get("issuerId"))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    try:
        before = live_snapshot(api)
        current = map_localizations(before["appStoreVersionLocalizations"])
        plan = {"appId": APP_ID, "bundleId": BUNDLE_ID, "version": VERSION,
                "versionId": VERSION_ID, "apply": args.apply, "locales": []}
        for code in selected:
            if code not in current or code not in originals:
                raise RuntimeError("Selected existing localization is missing: " + code)
            resource, original = current[code], originals[code]
            if resource["id"] != original["id"]:
                raise RuntimeError("Localization ID differs from audit baseline: " + code)
            actual = resource["attributes"].get("description")
            if actual not in [original["attributes"].get("description"), desired[code]]:
                raise RuntimeError("Description changed since the audit; refusing overwrite: " + code)
            plan["locales"].append({"locale": code, "id": resource["id"],
                                    "action": "unchanged" if actual == desired[code] else "PATCH",
                                    "before": actual, "after": desired[code]})
        save(args.out_dir / ("before-" + stamp + ".json"), before)
        save(args.out_dir / ("plan-" + stamp + ".json"), plan)
        changes = [entry for entry in plan["locales"] if entry["action"] == "PATCH"]
        print("Target: " + BUNDLE_ID + " / iOS 3.3 / PREPARE_FOR_SUBMISSION", flush=True)
        print("Description PATCH count: " + str(len(changes)), flush=True)
        if not args.apply:
            print("Read-only plan saved; no remote metadata changed.", flush=True)
            return 0
        api.allowed_localization_ids = {entry["id"] for entry in changes}
        report = {"appId": APP_ID, "bundleId": BUNDLE_ID, "versionId": VERSION_ID,
                  "startedAt": stamp, "results": [], "submittedForReview": False,
                  "released": False, "screenshotsChanged": False}
        applied = {}
        write_error = None
        try:
            for entry in changes:
                require_target(api)
                path = "/appStoreVersionLocalizations/" + entry["id"]
                latest = api.request("GET", path)["data"]
                if latest["attributes"] != current[entry["locale"]]["attributes"]:
                    raise RuntimeError("Localization changed during upload: " + entry["locale"])
                body = {"data": {"type": "appStoreVersionLocalizations", "id": entry["id"],
                                  "attributes": {"description": entry["after"]}}}
                # Register expected final state before the call: a lost response can
                # follow a successful idempotent PATCH. Final GET resolves its outcome.
                applied[entry["locale"]] = entry["after"]
                api.request("PATCH", path, body)
                readback = api.request("GET", path)["data"]
                expected = dict(latest["attributes"])
                expected["description"] = entry["after"]
                if readback["id"] != entry["id"] or readback["attributes"] != expected:
                    raise RuntimeError("Immediate field readback failed: " + entry["locale"])
                report["results"].append({"locale": entry["locale"], "id": entry["id"], "verified": True})
                save(args.out_dir / ("upload-report-" + stamp + ".json"), report)
                print(entry["locale"] + ": description PATCH verified; other fields preserved", flush=True)
        except (APIError, RuntimeError) as error:
            write_error = str(error)
            report["writeError"] = write_error
        try:
            after = live_snapshot(api)
            save(args.out_dir / ("after-" + stamp + ".json"), after)
            issues = preservation_issues(before, after, applied)
            actual = map_localizations(after["appStoreVersionLocalizations"])
            desired_issues = [{"locale": code, "field": "description"} for code in selected
                              if actual.get(code, {}).get("attributes", {}).get("description") != desired[code]]
            report.update({"unexpectedFieldChanges": issues, "descriptionMismatches": desired_issues,
                           "verified": not issues and not desired_issues,
                           "completedAt": datetime.now(timezone.utc).isoformat()})
        except (APIError, RuntimeError) as error:
            report.update({"verified": False, "verificationError": str(error)})
        save(args.out_dir / ("upload-report-" + stamp + ".json"), report)
        save(args.out_dir / "upload-report.json", report)
        print("Verification: " + ("PASS" if report["verified"] else "FAIL"), flush=True)
        return 0 if report["verified"] else 1
    finally:
        api.session.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        # Never expose credentials, request headers, or raw network exception text.
        message = str(error) if isinstance(error, (APIError, RuntimeError)) else type(error).__name__
        print("ERROR: " + message, flush=True)
        sys.exit(1)
