#!/usr/bin/env bash
#
# 安装 dist/Interm.app 并注册 Finder 扩展。
#
# 默认装到 ~/Applications（不需要任何额外授权）；
# 传 --system 才装到 /Applications（可能触发「App 管理」权限提示）。
#
set -euo pipefail

cd "$(dirname "$0")/.."

PREFIX="$HOME/Applications"
for argument in "$@"; do
    case "$argument" in
        --system) PREFIX="/Applications" ;;
        --help|-h)
            echo "用法：$0 [--system]"
            exit 0
            ;;
        *)
            echo "未知参数：$argument" >&2
            exit 2
            ;;
    esac
done

APP_SOURCE="dist/Interm.app"
APP_TARGET="$PREFIX/Interm.app"
APPEX="$APP_TARGET/Contents/PlugIns/IntermFinder.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PBS="/System/Library/CoreServices/pbs"

if [[ ! -d "$APP_SOURCE" ]]; then
    echo "找不到 ${APP_SOURCE}，先运行 ./Scripts/build.sh" >&2
    exit 1
fi

echo "==> 安装到 ${APP_TARGET}"
mkdir -p "$PREFIX"
# 先退出正在运行的同名 App，避免替换后进程仍指向旧 inode
pkill -x Interm 2>/dev/null || true
rm -rf "$APP_TARGET"
ditto "$APP_SOURCE" "$APP_TARGET"
find "$APP_TARGET" -print0 | xargs -0 -I{} xattr -c "{}" 2>/dev/null || true

echo "==> 向 LaunchServices 注册"
"$LSREGISTER" -f "$APP_TARGET"

echo "==> 注册 Finder 扩展"
pluginkit -a "$APPEX" >/dev/null 2>&1 || true
pluginkit -e use -i com.menmapro.Interm.Finder >/dev/null 2>&1 || true

echo "==> 刷新服务菜单"
"$PBS" -flush >/dev/null 2>&1 || true

echo
echo "==> 当前扩展状态"
pluginkit -m -A -v -p com.apple.FinderSync 2>/dev/null | grep -i "menmapro.Interm" || echo "    （未出现在 pluginkit 列表，见下方说明）"

cat <<'EOF'

接下来三步（按需选择）：

1) 菜单栏按钮（推荐，单击即开）
   打开「应用程序」文件夹，按住 ⌘ 把 Interm.app 拖到 Finder 窗口工具栏；
   之后单击这个图标就在当前 Finder 目录打开终端。
   首次点击会弹一次「Interm 想要控制访达」，允许即可。

2) Finder 原生扩展（右键菜单 + 工具栏下拉）
   系统设置 › 通用 › 登录项与扩展 › 扩展 › 访达扩展，勾选 Interm；
   或在 Interm 设置窗口点「启用 / 管理扩展…」。
   扩展若显示「未注册 / 未启用」，多半是系统还没刷新：
     pluginkit -a ~/Applications/Interm.app/Contents/PlugIns/IntermFinder.appex
     killall pkd; killall Finder

3) 服务菜单
   Finder 里右键 › 服务 › 在终端中打开（默认快捷键 ⌃⌥T）。

验证：./Scripts/selftest.sh
EOF
