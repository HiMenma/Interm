#!/usr/bin/env bash
#
# 打包发布资产：zip + SHA256。
#
# 用法：
#   ./Scripts/dist.sh                       # 默认 1.0.0 + 当前时间戳
#   VERSION=1.2.0 BUILD_NUMBER=42 ./Scripts/dist.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCH="$(uname -m)"
NAME="Interm-${VERSION}-${ARCH}.zip"
ZIP="dist/${NAME}"

echo "==> 构建 ${VERSION} (${BUILD_NUMBER})"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" ./Scripts/build.sh

echo "==> 打包 ${NAME}"
mkdir -p dist
rm -f "$ZIP" "${ZIP}.sha256"
# --norsrc/--noextattr/--noqtn/--noacl：不要把这些元数据写成 zip 里的 ._ 文件，
# 否则用 Info-ZIP 解压后会多出 AppleDouble 文件，code signature 立刻失效。
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl dist/Interm.app "$ZIP"

echo "==> 计算校验和"
( cd dist && shasum -a 256 "$NAME" > "${NAME}.sha256" )

echo "==> 回读校验（解压后签名必须仍然有效）"
VERIFY_DIR="$(mktemp -d)"
unzip -q "$ZIP" -d "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Interm.app"
"$VERIFY_DIR/Interm.app/Contents/MacOS/Interm" --version
rm -rf "$VERIFY_DIR"

SIZE="$(du -h "$ZIP" | cut -f1)"
echo
echo "发布资产："
echo "  ${ZIP}  (${SIZE})"
echo "  ${ZIP}.sha256"
cat "dist/${NAME}.sha256"
echo
echo "下一步："
echo "  gh release create v${VERSION} --title \"Interm ${VERSION}\" \\"
echo "    --notes-file docs/release-notes/v${VERSION}.md \\"
echo "    \"${ZIP}\" \"${ZIP}.sha256\""
