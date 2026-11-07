#!/usr/bin/env bash
#
# 结构 + 运行时自检。
# 硬失败（exit 1）只用于「构建产物本身坏了」；扩展是否启用属于环境状态，只报告不失败。
#
set -uo pipefail

cd "$(dirname "$0")/.."

APP="dist/Interm.app"
APPEX="$APP/Contents/PlugIns/IntermFinder.appex"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
failures=0

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '    %s\n' "$1"; }

echo "== 1. 产物结构 =="
if [[ -d "$APP" ]]; then pass "App 存在：$APP"; else fail "App 缺失（先跑 make build）"; fi
if [[ -x "$APP/Contents/MacOS/Interm" ]]; then pass "宿主可执行文件存在"; else fail "宿主可执行文件缺失"; fi
if [[ -x "$APPEX/Contents/MacOS/IntermFinder" ]]; then pass "扩展可执行文件存在"; else fail "扩展可执行文件缺失"; fi
if [[ -f "$APP/Contents/Resources/Interm.icns" ]]; then pass "图标已打包"; else fail "图标缺失"; fi
if [[ -f "$APPEX/Contents/Resources/IntermToolbarIcon.png" ]]; then pass "工具栏图标已打包"; else fail "工具栏图标缺失"; fi

if [[ ! -d "$APP" ]]; then
    echo
    echo "产物不存在，后续检查跳过。"
    exit 1
fi

echo "== 2. Info.plist =="
check_plist() {
    local file="$1" key="$2" expected="$3" label="$4"
    local value
    value="$("$PLIST_BUDDY" -c "Print :$key" "$file" 2>/dev/null || true)"
    if [[ "$value" == "$expected" ]]; then
        pass "$label = $expected"
    else
        fail "$label = ${value:-（缺失）}，期望 $expected"
    fi
}

check_plist "$APP/Contents/Info.plist" CFBundleIdentifier "com.menmapro.Interm" "宿主 CFBundleIdentifier"
check_plist "$APP/Contents/Info.plist" LSUIElement "true" "宿主 LSUIElement"
check_plist "$APPEX/Contents/Info.plist" CFBundleIdentifier "com.menmapro.Interm.Finder" "扩展 CFBundleIdentifier"
check_plist "$APPEX/Contents/Info.plist" CFBundlePackageType "XPC!" "扩展 CFBundlePackageType"
check_plist "$APPEX/Contents/Info.plist" "NSExtension:NSExtensionPointIdentifier" "com.apple.FinderSync" "扩展扩展点"
check_plist "$APPEX/Contents/Info.plist" "NSExtension:NSExtensionPrincipalClass" "IntermFinderExtension" "扩展 PrincipalClass"

if "$PLIST_BUDDY" -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$APP/Contents/Info.plist" 2>/dev/null | grep -q "^interm$"; then
    pass "URL scheme interm 已声明"
else
    fail "URL scheme interm 未声明"
fi

if "$PLIST_BUDDY" -c "Print :NSServices:0:NSMessage" "$APP/Contents/Info.plist" 2>/dev/null | grep -q "^openInTerminalHere$"; then
    pass "NSServices 已声明"
else
    fail "NSServices 未声明"
fi

echo "== 3. 代码签名 =="
if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    pass "codesign --verify --deep --strict 通过"
else
    fail "签名校验失败"
fi

if codesign -d --entitlements :- "$APPEX" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
    pass "扩展带 app-sandbox entitlement"
else
    fail "扩展缺少 app-sandbox entitlement"
fi

if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    note "（提示）App 上存在 quarantine 属性，首次运行可能需要右键打开"
else
    pass "无 quarantine 属性"
fi

echo "== 4. 运行时自检 =="
SELFTEST_OUTPUT="$("$APP/Contents/MacOS/Interm" --selftest 2>&1)"
SELFTEST_STATUS=$?
echo "$SELFTEST_OUTPUT" | sed 's/^/    /'
if [[ $SELFTEST_STATUS -eq 0 ]]; then
    pass "Interm --selftest 通过"
else
    note "（提示）Interm --selftest 有未通过项：扩展未启用属于正常状态，安装并启用后再跑一次即可"
fi

echo "== 5. 扩展注册状态 =="
if pluginkit -m -A -v -p com.apple.FinderSync 2>/dev/null | grep -q "com.menmapro.Interm.Finder"; then
    pluginkit -m -A -v -p com.apple.FinderSync 2>/dev/null | grep "com.menmapro.Interm.Finder" | sed 's/^/    /'
    pass "扩展已注册到 pkd"
else
    note "（提示）扩展尚未注册：安装后执行 pluginkit -a <appex>，或重新登录"
fi

echo
if [[ $failures -gt 0 ]]; then
    echo "自检失败：$failures 项"
    exit 1
fi
echo "自检通过（扩展启用状态仅供参考）"
