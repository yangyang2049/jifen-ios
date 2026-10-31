"""Prepare iOS 3.4.1 and update only its approved What's New via ASC API.

No build upload/selection, review submission, release or Computer Use.
Private keys are loaded from the existing external config; JWTs stay in memory.
"""

import argparse
import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path


FOLDER = Path(__file__).resolve().parent
ROOT = FOLDER.parents[2]
APP_ID = "6759768784"
BUNDLE_ID = "com.douhua.jifen.ios"
VERSION = "3.4.1"
CONFIG = Path("/Users/yangyang/Documents/CERTIFICATES/AppStoreConnect_iScoreboard-localization.json")


def save(name, data):
    path = FOLDER / name
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def by_locale(rows):
    return {row["attributes"]["locale"]: row for row in rows}


def protected(rows):
    return {
        code: {k: v for k, v in row["attributes"].items() if k != "whatsNew"}
        for code, row in by_locale(rows).items()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    metadata = json.loads((FOLDER / "metadata.json").read_text())
    approved = json.loads((FOLDER / "draft.json").read_text())
    assert metadata["appId"] == approved["appId"] == APP_ID
    assert metadata["bundleId"] == approved["bundleId"] == BUNDLE_ID
    assert metadata["version"] == approved["version"] == VERSION
    assert approved["copyStatus"] == "approved_by_user"
    copies = {r["locale"]: r["whatsNew"] for r in metadata["localizations"]}
    assert len(copies) == len(metadata["localizations"]) == 50
    for row in approved["localizations"]:
        assert copies[row["locale"]] == row["whatsNew"]
    for text in copies.values():
        assert len(text.splitlines()) == 4
        assert all(line.startswith("• ") for line in text.splitlines())
        assert len(text.encode("utf-16-le")) // 2 <= 4000
        assert all(number in text for number in ["50", "1", "99"])

    spec = importlib.util.spec_from_file_location("asc_api", ROOT / "scripts/app_store_localization.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    config = json.loads(CONFIG.read_text())
    api = module.API(CONFIG.parent / config["privateKeyFile"], config["keyId"], config.get("issuerId"))
    app = api.request("GET", f"/apps/{APP_ID}")["data"]
    assert app["attributes"]["bundleId"] == BUNDLE_ID
    versions_path = f"/apps/{APP_ID}/appStoreVersions"
    versions = api.list(versions_path)
    live = next(v for v in versions if v["attributes"]["platform"] == "IOS"
                and v["attributes"]["versionString"] == "3.4")
    assert live["attributes"]["appStoreState"] == "READY_FOR_SALE"
    live_path = f'/appStoreVersions/{live["id"]}/appStoreVersionLocalizations'
    live_before = api.list(live_path)
    assert set(by_locale(live_before)) == set(copies)
    targets = [v for v in versions if v["attributes"]["platform"] == "IOS"
               and v["attributes"]["versionString"] == VERSION]
    assert len(targets) <= 1
    version = targets[0] if targets else None
    if version:
        assert version["attributes"]["appStoreState"] in module.EDITABLE
    else:
        assert not any(v["attributes"].get("platform") == "IOS"
                       and v["attributes"].get("appStoreState") in module.EDITABLE for v in versions)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    save(f"before-create-{stamp}.json", {"app": app, "versions": versions, "liveLocalizations": live_before})
    if not args.apply:
        save("upload-plan.json", {"version": VERSION, "willCreateVersion": version is None,
                                  "field": "whatsNew", "locales": sorted(copies), "apply": False})
        print(f"API plan: {APP_ID} / {BUNDLE_ID} / {VERSION}; 50 locales; What's New only.", flush=True)
        return

    created = version is None
    if version is None:
        body = {"data": {"type": "appStoreVersions", "attributes": {
            "platform": "IOS", "versionString": VERSION,
            "releaseType": live["attributes"]["releaseType"]
        }, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}}
        try:
            version = api.request("POST", "/appStoreVersions", body)["data"]
        except Exception:
            # Reconcile uncertain creation before any later run; never blind-retry POST.
            targets = [v for v in api.list(versions_path) if v["attributes"]["platform"] == "IOS"
                       and v["attributes"]["versionString"] == VERSION]
            if len(targets) != 1:
                raise
            version = targets[0]
    assert version["attributes"]["appStoreState"] in module.EDITABLE
    version_id = version["id"]
    path = f"/appStoreVersions/{version_id}/appStoreVersionLocalizations"
    before = api.list(path)
    save(f"before-upload-{stamp}.json", {"version": version, "localizations": before})
    existing = by_locale(before)
    published = by_locale(live_before)
    assert set(existing) <= set(copies)
    save("upload-plan.json", {"versionId": version_id, "version": VERSION,
                              "createdVersion": created, "field": "whatsNew", "apply": True,
                              "locales": [{"locale": code, "action": "PATCH" if code in existing else "POST"}
                                          for code in sorted(copies)]})
    results = []
    for index, code in enumerate(sorted(copies), 1):
        fields = {"whatsNew": copies[code]}
        if code not in existing:
            for key in ["description", "keywords", "marketingUrl", "promotionalText", "supportUrl"]:
                value = published[code]["attributes"].get(key)
                if value is not None:
                    fields[key] = value
        _, action = api.upsert("appStoreVersionLocalizations", "appStoreVersion", version_id,
                               code, fields, existing.get(code))
        results.append({"locale": code, "action": action})
        save("upload-report.json", {"versionId": version_id, "results": results,
                                    "submittedForReview": False, "released": False})
        print(f"{index:02d}/50 {code}: {action}", flush=True)

    after = api.list(path)
    live_after = api.list(live_path)
    version_after = api.request("GET", f"/appStoreVersions/{version_id}")["data"]
    save("after-upload.json", {"version": version_after, "localizations": after})
    observed = by_locale(after)
    mismatches = [code for code, text in copies.items()
                  if observed.get(code, {}).get("attributes", {}).get("whatsNew") != text]
    protected_after = protected(after)
    changed = [code for code, fields in protected(before).items() if protected_after.get(code) != fields]
    verification = {"versionId": version_id, "version": VERSION, "localeCount": len(observed),
                    "whatsNewMismatches": mismatches, "otherMetadataChanged": changed,
                    "published34Unchanged": by_locale(live_before) == by_locale(live_after),
                    "state": version_after["attributes"]["appStoreState"],
                    "releaseTypeUnchanged": version_after["attributes"]["releaseType"] == live["attributes"]["releaseType"],
                    "submittedForReview": False, "released": False,
                    "verifiedAt": datetime.now(timezone.utc).isoformat()}
    save("verification.json", verification)
    assert set(observed) == set(copies) and not mismatches and not changed
    assert verification["published34Unchanged"] and verification["releaseTypeUnchanged"]
    assert verification["state"] == "PREPARE_FOR_SUBMISSION"
    metadata.update(appStoreVersionId=version_id, uploadStatus="verified_50_locales",
                    verifiedAt=verification["verifiedAt"])
    save("metadata.json", metadata)
    print(json.dumps(verification, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
