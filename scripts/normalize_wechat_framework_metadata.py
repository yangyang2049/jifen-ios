#!/usr/bin/env python3
"""Align Xcode's embedded WeChat static-framework stub with its actual Mach-O minimum."""

import argparse
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"Invalid minimum OS version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def required_minimum(binary):
    result = subprocess.run(
        ["/usr/bin/xcrun", "vtool", "-show-build", str(binary)],
        check=True, capture_output=True, text=True,
    )
    values = re.findall(r"^\s*minos\s+(\d+(?:\.\d+){0,2})\s*$", result.stdout, re.MULTILINE)
    if not values:
        raise ValueError(f"No Mach-O minimum OS version found in {binary}")
    return max(values, key=version_tuple)


def normalize(framework, check_only=False):
    framework = Path(framework)
    if framework.name != "WechatOpenSDK.framework":
        raise ValueError("This workaround applies only to WechatOpenSDK.framework")
    plist_path = framework / "Info.plist"
    original = plist_path.read_bytes()
    info = plistlib.loads(original)
    if (info.get("CFBundleIdentifier") != "com.tencent.WechatOpenSDK"
            or info.get("CFBundleExecutable") != "WechatOpenSDK"):
        raise ValueError("Unexpected WeChat framework identity")
    minimum = required_minimum(framework / info["CFBundleExecutable"])
    declared = info.get("MinimumOSVersion")
    if version_tuple(declared) >= version_tuple(minimum):
        print(f"WeChat framework minimum OS is valid: plist {declared}, Mach-O {minimum}")
        return False
    if check_only:
        raise ValueError(f"WeChat minimum OS mismatch: plist {declared}, Mach-O requires {minimum}")

    signing = os.environ.get("CODE_SIGNING_ALLOWED") == "YES"
    identity = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY", "")
    if signing and not identity:
        raise ValueError("Cannot update a signed framework without Xcode's signing identity")
    info["MinimumOSVersion"] = minimum
    plist_path.chmod(plist_path.stat().st_mode | stat.S_IWUSR)
    fmt = plistlib.FMT_BINARY if original.startswith(b"bplist00") else plistlib.FMT_XML
    plist_path.write_bytes(plistlib.dumps(info, fmt=fmt, sort_keys=False))
    if signing:
        # The copy phase may have signed the framework before this build phase.
        # Re-sign the changed bundle before Xcode signs the enclosing app.
        subprocess.run([
            "/usr/bin/codesign", "--force", "--sign", identity, "--timestamp=none",
            "--preserve-metadata=identifier,entitlements,flags", str(framework),
        ], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(framework)], check=True)
    print(f"Normalized embedded WeChat minimum OS: {declared} -> {minimum}")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("framework", type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    try:
        normalize(args.framework, args.check_only)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
