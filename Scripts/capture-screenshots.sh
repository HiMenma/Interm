#!/usr/bin/env bash
#
# 抓 README 用的窗口截图（需要「屏幕录制」权限）。
#
# 会临时：
#   * 隐藏 Finder 侧边栏（避免把个人收藏目录拍进公开截图），结束后还原
#   * 起一个 Terminal 窗口（强制用 Terminal.app，不改用户的默认终端设置）
#   * 打开 Interm 设置窗口
# 抓完合成两张图到 docs/images/，然后关掉自己开的窗口。
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP="dist/Interm.app"
if [[ ! -d "$APP" ]]; then
    ./Scripts/build.sh
fi

SIDEBAR_WAS="$(defaults read com.apple.finder ShowSidebar 2>/dev/null || echo 1)"

cleanup() {
    if [[ "$SIDEBAR_WAS" != "0" ]]; then
        defaults write com.apple.finder ShowSidebar -bool true
    else
        defaults write com.apple.finder ShowSidebar -bool false
    fi
    killall Finder 2>/dev/null || true
    pkill -x Interm 2>/dev/null || true
}
trap cleanup EXIT

echo "==> 临时隐藏 Finder 侧边栏"
defaults write com.apple.finder ShowSidebar -bool false
killall Finder 2>/dev/null || true
sleep 2

echo "==> 打开仓库目录的 Finder 窗口"
open "$PWD"
sleep 2

echo "==> 在该目录打开终端（Terminal.app）"
"$PWD/$APP/Contents/MacOS/Interm" --open-at "$PWD" --terminal terminal >/dev/null 2>&1 || true
sleep 2

echo "==> 打开设置窗口"
pkill -x Interm 2>/dev/null || true
sleep 1
open -a "$HOME/Applications/Interm.app" --args --settings 2>/dev/null \
    || open "$PWD/$APP" --args --settings
sleep 3

echo "==> 抓图并合成"
swift Scripts/capture-screenshots.swift

echo
echo "完成："
echo "  docs/images/screenshot-finder-terminal.png"
echo "  docs/images/screenshot-settings.png"
