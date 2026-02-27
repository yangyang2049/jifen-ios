#!/bin/bash
# 自动化测试：平板 / 手机 × iOS 18 / 26 各跑一次
# 用法: ./run_automation_four_destinations.sh

set -e
cd "$(dirname "$0")"
PROJECT=jifen.xcodeproj
SCHEME=jifen
OUT_DIR="${1:-/tmp/jifen_test_results}"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

run_test() {
  local name="$1"
  local dest="$2"
  echo "=========================================="
  echo "[$(date '+%H:%M:%S')] 开始: $name"
  echo "  destination: $dest"
  echo "=========================================="
  if xcodebuild test -scheme "$SCHEME" -project "$PROJECT" \
    -destination "$dest" \
    -resultBundlePath "$OUT_DIR/${name}.xcresult" 2>&1 | tee "$OUT_DIR/${name}.log"; then
    echo "[$(date '+%H:%M:%S')] 通过: $name"
    return 0
  else
    echo "[$(date '+%H:%M:%S')] 失败: $name"
    return 1
  fi
}

FAIL=0

# 1. 手机 iOS 18
run_test "iphone_ios18" "platform=iOS Simulator,name=iPhone 16,OS=18.5" || FAIL=$((FAIL+1))

# 2. 平板 iOS 18
run_test "ipad_ios18" "platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.5" || FAIL=$((FAIL+1))

# 3. 手机 iOS 26
run_test "iphone_ios26" "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0" || FAIL=$((FAIL+1))

# 4. 平板 iOS 26
run_test "ipad_ios26" "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.0" || FAIL=$((FAIL+1))

echo "=========================================="
echo "全部完成. 结果目录: $OUT_DIR"
echo "失败次数: $FAIL / 4"
exit $FAIL
