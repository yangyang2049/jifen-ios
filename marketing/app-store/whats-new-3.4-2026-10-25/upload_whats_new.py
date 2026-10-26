"""Upload approved 3.4 What's New copy, without submitting a build or review."""

import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path


FOLDER = Path(__file__).resolve().parent
ROOT = FOLDER.parents[2]
APP_ID = "6759768784"
BUNDLE_ID = "com.douhua.jifen.ios"


def save(name, value):
    (FOLDER / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def locale_map(rows):
    return {row["attributes"]["locale"]: row for row in rows}


def protected(rows):
    return {
        locale: {key: value for key, value in row["attributes"].items() if key != "whatsNew"}
        for locale, row in locale_map(rows).items()
    }


def main():
    metadata = json.loads((FOLDER / "metadata.json").read_text())
    approved = json.loads((FOLDER / "draft.json").read_text())
    assert metadata["appId"] == APP_ID and metadata["bundleId"] == BUNDLE_ID
    assert metadata["version"] == "3.4" and approved["copyStatus"] == "approved_by_user"
    copies = {row["locale"]: row["whatsNew"] for row in metadata["localizations"]}
    assert len(copies) == len(metadata["localizations"]) == 50
    for row in approved["localizations"]:
        assert copies[row["locale"]] == row["whatsNew"]
    for locale, text in copies.items():
        assert len(text.encode("utf-16-le")) // 2 <= 4000
        assert len(text.splitlines()) == (7 if locale.startswith("zh-") else 6)
        assert all(line.startswith("• ") for line in text.splitlines())
        assert "14710" in text and "1357" in text
        if not locale.startswith("zh-"):
            assert "wechat" not in text.casefold() and "微信" not in text

    spec = importlib.util.spec_from_file_location("asc_api", ROOT / "scripts/app_store_localization.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    certs = Path("/Users/yangyang/Documents/CERTIFICATES")
    config = json.loads((certs / "AppStoreConnect_iScoreboard-localization.json").read_text())
    api = module.API(certs / config["privateKeyFile"], config["keyId"], config["issuerId"])
    app = api.request("GET", f"/apps/{APP_ID}")["data"]
    assert app["attributes"]["bundleId"] == BUNDLE_ID
    versions = api.list(f"/apps/{APP_ID}/appStoreVersions")
    live = next(v for v in versions if v["attributes"]["platform"] == "IOS"
                and v["attributes"]["versionString"] == "3.3")
    live_path = f'/appStoreVersions/{live["id"]}/appStoreVersionLocalizations'
    live_before = api.list(live_path)
    assert set(locale_map(live_before)) == set(copies)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    save(f"before-create-{stamp}.json", {"app": app, "versions": versions, "liveLocalizations": live_before})
    version = next((v for v in versions if v["attributes"]["platform"] == "IOS"
                    and v["attributes"]["versionString"] == "3.4"), None)
    created = False
    if version is None:
        body = {"data": {"type": "appStoreVersions", "attributes": {
            "platform": "IOS", "versionString": "3.4",
            "releaseType": live["attributes"]["releaseType"]
        }, "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}}
        try:
            version = api.request("POST", "/appStoreVersions", body)["data"]
            created = True
        except Exception:
            # Reconcile an unknown creation outcome before any possible retry.
            versions = api.list(f"/apps/{APP_ID}/appStoreVersions")
            version = next((v for v in versions if v["attributes"]["platform"] == "IOS"
                            and v["attributes"]["versionString"] == "3.4"), None)
            if version is None:
                raise
    assert version["attributes"]["appStoreState"] in module.EDITABLE
    version_id = version["id"]
    path = f"/appStoreVersions/{version_id}/appStoreVersionLocalizations"
    before = api.list(path)
    save(f"before-upload-{stamp}.json", {"version": version, "localizations": before})
    existing = locale_map(before)
    live_by_locale = locale_map(live_before)
    plan = {"versionId": version_id, "version": "3.4", "field": "whatsNew", "createdVersion": created,
            "locales": [{"locale": locale, "action": "PATCH" if locale in existing else "POST"}
                        for locale in sorted(copies)]}
    save("upload-plan.json", plan)
    results = []
    for index, locale in enumerate(sorted(copies), 1):
        fields = {"whatsNew": copies[locale]}
        if locale not in existing:
            # Copy only writable text fields when Apple did not inherit a locale.
            old = live_by_locale[locale]["attributes"]
            for key in ["description", "keywords", "marketingUrl", "promotionalText", "supportUrl"]:
                if old.get(key) is not None:
                    fields[key] = old[key]
        _, action = api.upsert("appStoreVersionLocalizations", "appStoreVersion", version_id,
                               locale, fields, existing.get(locale))
        results.append({"locale": locale, "action": action})
        save("upload-report.json", {"versionId": version_id, "results": results,
                                    "submittedForReview": False, "released": False})
        print(f"{index}/50 {locale}: {action}", flush=True)

    after = api.list(path)
    live_after = api.list(live_path)
    version_after = api.request("GET", f"/appStoreVersions/{version_id}")["data"]
    save("after-upload.json", {"version": version_after, "localizations": after})
    observed = locale_map(after)
    mismatches = [locale for locale, text in copies.items()
                  if observed.get(locale, {}).get("attributes", {}).get("whatsNew") != text]
    changed_protected = [locale for locale, fields in protected(before).items()
                         if protected(after).get(locale) != fields]
    verification = {"versionId": version_id, "version": "3.4", "localeCount": len(observed),
                    "whatsNewMismatches": mismatches, "otherMetadataChanged": changed_protected,
                    "published33Unchanged": locale_map(live_before) == locale_map(live_after),
                    "state": version_after["attributes"]["appStoreState"],
                    "releaseTypeUnchanged": version_after["attributes"]["releaseType"] == live["attributes"]["releaseType"],
                    "submittedForReview": False, "released": False,
                    "verifiedAt": datetime.now(timezone.utc).isoformat()}
    save("verification.json", verification)
    assert set(observed) == set(copies) and not mismatches and not changed_protected
    assert verification["published33Unchanged"] and verification["releaseTypeUnchanged"]
    assert verification["state"] == "PREPARE_FOR_SUBMISSION"
    metadata.update(appStoreVersionId=version_id, uploadStatus="verified_50_locales",
                    verifiedAt=verification["verifiedAt"])
    save("metadata.json", metadata)
    print(json.dumps(verification, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
