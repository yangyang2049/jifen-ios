#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_dir/UITestScreenshots-All"
result_dir="$repo_dir/build/ui-screenshot-results"

iphone_destination="${IPHONE_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5}"
ipad_destination="${IPAD_DESTINATION:-platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5}"

mkdir -p "$output_dir" "$result_dir"
find "$output_dir" -maxdepth 1 -type f \
  \( -name 'iPhone_*.png' -o -name 'iPad_*.png' -o -name 'INDEX.txt' \) \
  -delete
find "$result_dir" -maxdepth 1 -type d -name '*.xcresult' -exec rm -rf {} +

run_device() {
  local label="$1"
  local destination="$2"
  local test_action="$3"
  local result_bundle="$result_dir/$label.xcresult"
  local attachment_dir="$result_dir/$label-attachments"
  local log_file="$result_dir/$label.log"

  echo "Running screenshot UI tests for $label"
  if ! xcodebuild "$test_action" \
    -project "$repo_dir/jifen.xcodeproj" \
    -scheme jifen \
    -destination "$destination" \
    -only-testing:jifenUITests/FullAppScreenshotUITests/testCaptureFullAppScreenshots \
    -resultBundlePath "$result_bundle" \
    > "$log_file" 2>&1; then
    tail -120 "$log_file" >&2
    return 1
  fi

  rm -rf "$attachment_dir"
  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachment_dir" \
    > "$result_dir/$label-export.log"

  while IFS=$'\t' read -r exported_name suggested_name; do
    [[ -n "$exported_name" && -n "$suggested_name" ]] || continue
    local screenshot_name="${suggested_name%%_0_*}"
    screenshot_name="${screenshot_name#iPhone_}"
    screenshot_name="${screenshot_name#iPad_}"
    cp "$attachment_dir/$exported_name" "$output_dir/${label}_${screenshot_name}.png"
  done < <(
    jq -r '
      .[] | .attachments[] |
      select(.exportedFileName | endswith(".png")) |
      select(.suggestedHumanReadableName | test("_0_[0-9A-F-]+\\.png$")) |
      [.exportedFileName, .suggestedHumanReadableName] | @tsv
    ' "$attachment_dir/manifest.json"
  )

  local exported_count
  exported_count="$(find "$output_dir" -maxdepth 1 -type f -name "${label}_*.png" | wc -l | tr -d ' ')"
  echo "Finished $label: $exported_count review screenshots"
}

run_device "iPhone" "$iphone_destination" "test"
# The same iOS Simulator build product is valid on iPad. Reusing it saves a
# second full build and avoids unrelated embedded-Watch recompilation.
run_device "iPad" "$ipad_destination" "test-without-building"

iphone_count="$(find "$output_dir" -maxdepth 1 -type f -name 'iPhone_*.png' | wc -l | tr -d ' ')"
ipad_count="$(find "$output_dir" -maxdepth 1 -type f -name 'iPad_*.png' | wc -l | tr -d ' ')"
total_count="$((iphone_count + ipad_count))"

{
  echo "iOS UI screenshot review index"
  echo "generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "iPhone count: $iphone_count"
  echo "iPad count: $ipad_count"
  echo "total count: $total_count"
  echo
  find "$output_dir" -maxdepth 1 -type f -name '*.png' -exec basename {} \; | sort
} > "$output_dir/INDEX.txt"

if [[ "$iphone_count" -lt 89 || "$ipad_count" -lt 89 ]]; then
  echo "Screenshot coverage incomplete: iPhone=$iphone_count, iPad=$ipad_count" >&2
  exit 1
fi

echo "Screenshot review folder: $output_dir"
echo "Screenshot totals: iPhone=$iphone_count, iPad=$ipad_count, all=$total_count"
