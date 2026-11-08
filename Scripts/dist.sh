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
ditto -c -k --keepParent dist/Interm.app "$ZIP"

echo "==> 计算校验和"
( cd dist && shasum -a 256 "$NAME" > "${NAME}.sha256" )

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
