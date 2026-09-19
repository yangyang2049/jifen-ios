#!/bin/bash
# 显示端批量截图：构建 → 安装到模拟器 → 逐个 fixture 启动 → simctl 截图。
# 用法:
#   ./scripts/display_snapshot.sh                 # 全部乒乓球 fixture
#   FIXTURES="pingpong_live pingpong_timeout" ./scripts/display_snapshot.sh
#   SIM_NAME="iPhone SE (3rd generation)" ./scripts/display_snapshot.sh
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="jifen.xcodeproj"
SCHEME="jifen"
CONFIGURATION="Debug"
BUNDLE_ID="com.douhua.jifen.ios"
SIM_NAME="${SIM_NAME:-}"
OUT_DIR="${OUT_DIR:-build/display_snapshots}"
FIXTURES="${FIXTURES:-pingpong_live pingpong_game_point pingpong_match_point pingpong_deuce pingpong_timeout pingpong_game_break pingpong_finished pingpong_doubles_live pingpong_doubles_timeout pingpong_doubles_finished}"

# 1) 构建（模拟器）
echo "==> Building project..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS Simulator' build -quiet
APP_PATH=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS Simulator' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2}' | head -1)/jifen.app
echo "==> App: $APP_PATH"

# 2) 选择模拟器（显式指定优先，否则取已启动设备/第一台可用 iPhone）
select_simulator() {
  if [ -n "$SIM_NAME" ]; then
    echo "$SIM_NAME"
    return
  fi

  local booted_udid
  booted_udid=$(xcrun simctl list devices available \
    | sed -nE 's/^.*\(([0-9A-Fa-f-]{36})\) \(Booted\).*$/\1/p' \
    | sed -n '1p')
  if [ -n "$booted_udid" ]; then
    echo "$booted_udid"
    return
  fi

  xcrun simctl list devices available \
    | sed -nE '/iPhone/ s/^.*\(([0-9A-Fa-f-]{36})\) \((Booted|Shutdown)\).*$/\1/p' \
    | sed -n '1p'
}
SIM=$(select_simulator)
if [ -z "$SIM" ]; then
  echo "No available iOS simulator found" >&2
  exit 1
fi
echo "==> Simulator: $SIM"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b

# 3) 安装并逐 fixture 截图
echo "==> Installing app..."
xcrun simctl install "$SIM" "$APP_PATH"
STATUS_BAR_OVERRIDDEN=0
cleanup_status_bar() {
  if [ "$STATUS_BAR_OVERRIDDEN" -eq 1 ]; then
    xcrun simctl status_bar "$SIM" clear >/dev/null 2>&1 || true
  fi
}
trap cleanup_status_bar EXIT
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryLevel 100
STATUS_BAR_OVERRIDDEN=1

mkdir -p "$OUT_DIR"
for fixture in $FIXTURES; do
  xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
  echo "==> Screenshot: $fixture"
  xcrun simctl launch "$SIM" "$BUNDLE_ID" -DisplaySnapshotFixture "$fixture" >/dev/null
  sleep 2.5
  xcrun simctl io "$SIM" screenshot "$OUT_DIR/$fixture.png" >/dev/null
done

xcrun simctl status_bar "$SIM" clear
STATUS_BAR_OVERRIDDEN=0
trap - EXIT
echo "==> Done. Screenshots in $OUT_DIR/"
ls -la "$OUT_DIR"
