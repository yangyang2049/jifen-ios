#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/test_artifacts.sh"
if [[ -z "${LOCALIZATION_VISUAL_AUDIT_DIR:-}" ]]; then
  start_test_artifacts localization-audit
  audit_dir="$TEST_ARTIFACT_RUN/audit"
else
  audit_dir="$LOCALIZATION_VISUAL_AUDIT_DIR"
fi
screenshot_dir="$audit_dir/screenshots"
result_dir="$audit_dir/results"

iphone_destination="${IPHONE_DESTINATION:-platform=iOS Simulator,name=iPhone 17e,OS=26.5}"
ipad_destination="${IPAD_DESTINATION:-platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5}"
locales=(ja ko de it nl sv fr fr-CA es-MX es-ES pt-BR pt-PT ru uk ar he ur ca pl ro cs sk sl hr da nb fi hu el hi bn mr gu pa ta te kn ml or tr vi th id ms)

if [[ -n "${LOCALIZATION_VISUAL_AUDIT_LOCALES:-}" ]]; then
  IFS=',' read -r -a locales <<< "$LOCALIZATION_VISUAL_AUDIT_LOCALES"
fi

for locale in "${locales[@]}"; do
  if ! python3 "$repo_dir/scripts/localization/localize.py" validate \
    --locale "$locale" \
    --require-reviewed >/dev/null; then
    echo "Visual audit blocked: $locale still has unreviewed or invalid localization rows." >&2
    exit 2
  fi
  resource_dir="$repo_dir/jifen/Resources/$locale.lproj"
  if [[ ! -f "$resource_dir/Localizable.strings" || ! -f "$resource_dir/InfoPlist.strings" ]]; then
    echo "Visual audit blocked: $locale passed review but has not been promoted into Resources." >&2
    exit 2
  fi
done

test_targets=()
for locale in "${locales[@]}"; do
  case "$locale" in
    ja) test_method="testCaptureJa" ;;
    ko) test_method="testCaptureKo" ;;
    de) test_method="testCaptureDe" ;;
    it) test_method="testCaptureIt" ;;
    nl) test_method="testCaptureNl" ;;
    sv) test_method="testCaptureSv" ;;
    fr) test_method="testCaptureFr" ;;
    fr-CA) test_method="testCaptureFrCA" ;;
    ru) test_method="testCaptureRu" ;;
    uk) test_method="testCaptureUk" ;;
    es-MX) test_method="testCaptureEsMX" ;;
    es-ES) test_method="testCaptureEsES" ;;
    pt-BR) test_method="testCapturePtBR" ;;
    pt-PT) test_method="testCapturePtPT" ;;
    ar) test_method="testCaptureAr" ;;
    he) test_method="testCaptureHe" ;;
    ur) test_method="testCaptureUr" ;;
    ca) test_method="testCaptureCa" ;;
    pl) test_method="testCapturePl" ;;
    ro) test_method="testCaptureRo" ;;
    cs) test_method="testCaptureCs" ;;
    sk) test_method="testCaptureSk" ;;
    sl) test_method="testCaptureSl" ;;
    hr) test_method="testCaptureHr" ;;
    da) test_method="testCaptureDa" ;;
    nb) test_method="testCaptureNb" ;;
    fi) test_method="testCaptureFi" ;;
    hu) test_method="testCaptureHu" ;;
    el) test_method="testCaptureEl" ;;
    hi) test_method="testCaptureHi" ;;
    bn) test_method="testCaptureBn" ;;
    mr) test_method="testCaptureMr" ;;
    gu) test_method="testCaptureGu" ;;
    pa) test_method="testCapturePa" ;;
    ta) test_method="testCaptureTa" ;;
    te) test_method="testCaptureTe" ;;
    kn) test_method="testCaptureKn" ;;
    ml) test_method="testCaptureMl" ;;
    or) test_method="testCaptureOr" ;;
    tr) test_method="testCaptureTr" ;;
    vi) test_method="testCaptureVi" ;;
    th) test_method="testCaptureTh" ;;
    id) test_method="testCaptureId" ;;
    ms) test_method="testCaptureMs" ;;
    *)
      echo "Visual audit blocked: no XCTest entry point for $locale." >&2
      exit 2
      ;;
  esac
  test_targets+=("-only-testing:jifenUITests/LocalizationVisualAuditUITests/$test_method")
done

if [[ "${LOCALIZATION_VISUAL_AUDIT_PRESERVE:-0}" != "1" ]]; then
  rm -rf "$audit_dir"
fi
mkdir -p "$screenshot_dir" "$result_dir"

run_device() {
  local label="$1"
  local destination="$2"
  local action="$3"
  local result_bundle="$result_dir/$label.xcresult"
  local attachment_dir="$result_dir/$label-attachments"
  local log_file="$result_dir/$label.log"

  # xcresult refuses to overwrite an existing bundle. In preserve mode only
  # the selected locales are replaced; screenshots for prior locales remain.
  rm -rf "$result_bundle" "$attachment_dir"

  echo "Running localization visual audit for $label"
  if ! xcodebuild "$action" \
      -project "$repo_dir/jifen.xcodeproj" \
      -scheme jifen \
      -destination "$destination" \
      "${test_targets[@]}" \
      -resultBundlePath "$result_bundle" \
      > "$log_file" 2>&1; then
    tail -160 "$log_file" >&2
    return 1
  fi

  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachment_dir" \
    > "$result_dir/$label-export.log"

  while IFS=$'\t' read -r exported_name suggested_name; do
    [[ -n "$exported_name" && -n "$suggested_name" ]] || continue
    local extension="${suggested_name##*.}"
    local readable_name
    readable_name="$(printf '%s' "$suggested_name" | sed -E "s/_0_[0-9A-Fa-f-]{36}\\.${extension}$/.${extension}/")"
    case "$extension" in
      png) cp "$attachment_dir/$exported_name" "$screenshot_dir/$readable_name" ;;
      json) cp "$attachment_dir/$exported_name" "$audit_dir/$readable_name" ;;
    esac
  done < <(
    jq -r '
      .[] | .attachments[] |
      select((.exportedFileName | endswith(".png")) or (.exportedFileName | endswith(".json"))) |
      [.exportedFileName, .suggestedHumanReadableName] | @tsv
    ' "$attachment_dir/manifest.json"
  )
}

run_device "iPhone" "$iphone_destination" "test"
run_device "iPad" "$ipad_destination" "test-without-building"

node "$repo_dir/scripts/generate_localization_visual_audit.js" "$screenshot_dir" "$audit_dir"

echo "Localization visual audit: $audit_dir/本地化UI截图审查.md"
