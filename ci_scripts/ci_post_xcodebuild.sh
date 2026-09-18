#!/bin/zsh
# Xcode Cloud 编译成功后执行。在这里把 ipa 归档到临时目录便于排查；
# 分发到 TestFlight 的动作请在 Xcode Cloud 工作流里配置 Post-Actions，
# 而不是在本脚本里手动上传。

set -euo pipefail

echo "=== 构建结果 ==="
echo "工作流: ${CI_WORKFLOW:-未知}"
echo "构建号: ${CI_BUILD_NUMBER:-未知}"

IPA_DIR="${CI_ARCHIVE_PATH:-${CI_DERIVED_DATA_PATH:-/tmp}}"
echo "产物路径: $IPA_DIR"

if [ -d "$IPA_DIR" ]; then
  echo "--- 生成物列表:"
  find "$IPA_DIR" -maxdepth 2 -name "*.ipa" -o -maxdepth 2 -name "*.xcarchive" 2>/dev/null | head -20 \
    || echo "(未找到 ipa / xcarchive)"
fi

echo "提示：要在手机上直接下载，请在 Xcode Cloud 工作流里把 Post-Action 设为"
echo "      TestFlight (External)，并确保 Bundle ID 未在别人名下占用。"
