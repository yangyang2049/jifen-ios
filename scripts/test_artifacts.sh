#!/usr/bin/env bash
# Source from capture scripts; preserve the script's exit status and failed evidence.
start_test_artifacts() {
  TEST_ARTIFACT_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_artifacts.py"
  TEST_ARTIFACT_RUN="$(python3 "$TEST_ARTIFACT_HELPER" new-run "$1" --active)"
  trap 'finish_test_artifacts "$?"' EXIT
}

finish_test_artifacts() {
  local status="$1"
  local flags=(finish "$TEST_ARTIFACT_RUN")
  if [[ "$status" -ne 0 ]]; then flags+=(--failed); fi
  if ! python3 "$TEST_ARTIFACT_HELPER" "${flags[@]}" >/dev/null; then
    echo "Test-artifact cleanup failed; evidence remains at $TEST_ARTIFACT_RUN" >&2
  fi
  return "$status"
}
