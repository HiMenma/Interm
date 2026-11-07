#!/usr/bin/env bash
#
# 卸载：先让系统忘掉扩展与 App，再删文件。
# 顺序很重要，反了会留下 System Settings 里的幽灵扩展。
#
set -euo pipefail

PREFIX="$HOME/Applications"
for argument in "$@"; do
    case "$argument" in
        --system) PREFIX="/Applications" ;;
    esac
done

APP="$PREFIX/Interm.app"
APPEX="$APP/Contents/PlugIns/IntermFinder.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> 停用并注销扩展"
pluginkit -e ignore -i com.menmapro.Interm.Finder 2>/dev/null || true
if [[ -d "$APPEX" ]]; then
    pluginkit -r "$APPEX" 2>/dev/null || true
fi

echo "==> 退出 App"
pkill -x Interm 2>/dev/null || true

echo "==> 从 LaunchServices 注销"
if [[ -d "$APP" ]]; then
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
fi

echo "==> 删除文件"
rm -rf "$APP"

echo "==> 刷新插件守护进程"
killall pkd 2>/dev/null || true

echo "==> 清理偏好设置"
defaults delete com.menmapro.Interm 2>/dev/null || true

echo
echo "已卸载。若「系统设置 › 扩展」里仍残留条目，注销并重新登录即可消失。"
echo "提示：Finder 工具栏上手动拖入的图标需要按住 ⌘ 自行移除。"
