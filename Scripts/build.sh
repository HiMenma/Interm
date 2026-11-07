#!/usr/bin/env bash
#
# 组装 dist/Interm.app。
#
# SwiftPM 只负责产出两个 Mach-O 可执行文件，这里手工组装成 .app / .appex：
# 写 Info.plist、装图标、按「由内向外」的顺序做 ad-hoc 签名，最后校验。
#
# 用法：
#   ./Scripts/build.sh               正常构建
#   FORCE_ICONS=1 ./Scripts/build.sh 强制重画图标
#   VERSION=1.2.0 BUILD_NUMBER=42 ./Scripts/build.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
DIST_DIR="dist"
APP="$DIST_DIR/Interm.app"
APPEX="$APP/Contents/PlugIns/IntermFinder.appex"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

echo "==> 编译（release）"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

for binary in Interm IntermFinder; do
    if [[ ! -x "$BIN_DIR/$binary" ]]; then
        echo "构建产物缺失：$BIN_DIR/$binary" >&2
        exit 1
    fi
done

# 扩展的 LC_MAIN 必须指向 _NSExtensionMain；如果哪天有人改回 Swift main()，
# ExtensionFoundation 会在 EXExtensionMain 里直接 brk（实测踩过一次）。
echo "==> 校验扩展入口点"
ENTRY_GUARD="$(otool -tvV "$BIN_DIR/IntermFinder" | awk '
    /^_main:/ { inside = 1; next }
    inside && /^_/ && /:$/ { inside = 0 }
    inside && /bl[[:space:]]/ { print; inside = 0 }
')"
if [[ -n "$ENTRY_GUARD" ]]; then
    echo "错误：IntermFinder 的 Swift main() 里出现了函数调用，入口点不再是 _NSExtensionMain。" >&2
    echo "      请检查 Package.swift 的 linkerSettings（-e _NSExtensionMain），" >&2
    echo "      并确认 Sources/IntermFinder 下没有带顶层代码的 main.swift。" >&2
    exit 1
fi

echo "==> 准备图标"
if [[ ! -f Bundle/Interm.icns || ! -f Bundle/IntermToolbarTemplate.png || "${FORCE_ICONS:-0}" == "1" ]]; then
    swift Scripts/make-icons.swift
fi

echo "==> 组装 App Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"

cp "$BIN_DIR/Interm" "$APP/Contents/MacOS/Interm"
cp Bundle/Interm-Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Bundle/Interm.icns "$APP/Contents/Resources/Interm.icns"

"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

echo "==> 组装 Finder 扩展"
cp "$BIN_DIR/IntermFinder" "$APPEX/Contents/MacOS/IntermFinder"
cp Bundle/IntermFinder-Info.plist "$APPEX/Contents/Info.plist"
cp Bundle/IntermToolbarTemplate.png "$APPEX/Contents/Resources/IntermToolbarTemplate.png"

"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$APPEX/Contents/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$APPEX/Contents/Info.plist"

echo "==> 签名（ad-hoc，由内向外）"
find "$APP" -print0 | xargs -0 -I{} xattr -c "{}" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APPEX/Contents/MacOS/IntermFinder"
codesign --force --sign - --timestamp=none --entitlements Bundle/IntermFinder.entitlements "$APPEX"
codesign --force --sign - --timestamp=none "$APP"

echo "==> 校验签名"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
find "$APP" -print0 | xargs -0 -I{} xattr -c "{}" 2>/dev/null || true

if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    echo "警告：App 上仍带有 quarantine 属性，首次运行可能被 Gatekeeper 拦截" >&2
fi

echo
echo "构建完成：${APP}（版本 ${VERSION} / ${BUILD_NUMBER}）"
echo "  宿主二进制：${APP}/Contents/MacOS/Interm"
echo "  Finder 扩展：${APPEX}"
echo
echo "下一步："
echo "  ./Scripts/install.sh     安装到 ~/Applications 并注册扩展"
echo "  ./Scripts/selftest.sh    结构与自检"
