#!/bin/zsh
# Xcode Cloud 会在拉取代码后自动执行本脚本。
# 这里只做环境自检与工程校验，不做破坏性操作。

set -euo pipefail

echo "=== Xcode Cloud 环境 ==="
echo "构建号: ${CI_BUILD_NUMBER:-未知}"
echo "工作流: ${CI_WORKFLOW:-未知}"
echo "分支:   ${CI_BRANCH:-未知}"
echo "Xcode:  $(xcodebuild -version | head -1)"
echo "Swift:  $(swift --version 2>/dev/null | head -1)"

cd "$CI_WORKSPACE" 2>/dev/null || cd "$(dirname "$0")/.."

echo "=== 检查工程与共享 scheme ==="
if [ ! -d "CheckInReminder.xcodeproj" ]; then
  echo "错误：找不到 CheckInReminder.xcodeproj"
  exit 1
fi

SCHEME_COUNT=$(find CheckInReminder.xcodeproj -name "*.xcscheme" | wc -l | tr -d ' ')
echo "共享 scheme 数量: $SCHEME_COUNT"
if [ "$SCHEME_COUNT" -eq 0 ]; then
  echo "错误：没有共享 scheme，Xcode Cloud 无法识别构建目标。"
  echo "请在本地执行 xcodegen generate 后，把 xcshareddata/xcschemes 一并提交。"
  exit 1
fi

echo "=== 检查关键配置 ==="
/usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes' CheckInReminder/Info.plist 2>/dev/null \
  && echo "后台定位模式已配置" || echo "警告：未找到 UIBackgroundModes"

echo "=== 资源文件 ==="
ls -la CheckInReminder/Resources/*.wav 2>/dev/null | wc -l | xargs echo "内置铃声数量:"

echo "自检通过，开始编译。"
