#!/usr/bin/env python3
"""Run and verify the mandatory iPhone multiplayer-score UI regression."""
import argparse
import json
from pathlib import Path
import subprocess

from test_artifacts import finish_run, new_run

ROOT = Path(__file__).resolve().parents[1]
CASES = (
    "testReleaseMultiScoreFirstTouch",
    "testReleaseMultiScorePaging",
    "testReleaseMultiScoreDoubleExit",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="iPhone simulator UDID")
    parser.add_argument("--derived-data", default=str(Path.home() / "Library/Developer/Xcode/DerivedData/jifen-phone-check"))
    args = parser.parse_args()

    run = new_run("multi-score-release", active=True)
    result = run / "MultiScore.xcresult"
    log = run / "xcodebuild.log"
    failed = True
    print(f"Evidence: {run}", flush=True)
    try:
        with log.open("w") as output:
            command = [
                "xcodebuild", "-project", "jifen.xcodeproj", "-scheme", "jifen",
                "-destination", f"platform=iOS Simulator,id={args.simulator}",
                "-derivedDataPath", args.derived_data, "-resultBundlePath", str(result),
                "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                "-maximum-test-execution-time-allowance", "180",
                *(f"-only-testing:jifenUITests/FullAppScreenshotUITests/{case}()" for case in CASES),
                "test",
            ]
            completed = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        if completed.returncode:
            raise SystemExit(f"xcodebuild failed ({completed.returncode}). See {log}")
        summary = json.loads(subprocess.check_output([
            "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result),
        ]))
        counts = {key: summary.get(key) for key in
                  ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")}
        if counts != dict(totalTestCount=len(CASES), passedTests=len(CASES),
                          failedTests=0, skippedTests=0, expectedFailures=0):
            raise SystemExit(f"Incomplete multiplayer release gate: {counts}. See {result}")
        failed = False
        print(f"Multiplayer release gate passed ({len(CASES)} cases).")
    finally:
        finish_run(run, failed=failed)


if __name__ == "__main__":
    main()
