#!/usr/bin/env bash
#
# 把 Infinity X for zeus 需要的改动覆盖到源码树里。
#
#   repo init -u https://github.com/ProjectInfinity-X/manifest -b 16
#   bash apply.sh          # 第一次：只放 local manifest
#   repo sync -c -j8
#   bash apply.sh          # 第二次：manifest + 全部设备树文件
#   source build/envsetup.sh
#   lunch infinity_zeus-userdebug
#   mka bacon -j8
#
# 可以重复跑，不会重复叠加。
#
set -uo pipefail

TREE="${TREE:-$PWD}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MISSING=0

[ -d "$TREE/.repo" ] || {
    echo "✗ $TREE 下没有 .repo" >&2
    echo "  先在那个目录跑：repo init -u https://github.com/ProjectInfinity-X/manifest -b 16" >&2
    exit 1
}

# 把 overlays 下某个文件覆盖到树里。源目录没 sync 下来就记一笔，不中断。
put() {
    local rel="$1" note="$2"
    local src="$HERE/overlays/$rel"
    local dst="$TREE/$rel"

    if [ ! -d "$(dirname "$dst")" ]; then
        echo "⚠  跳过 $(dirname "$rel") —— 这个仓库还没拉下来（$note）" | sed 's/^/  /'
        MISSING=$((MISSING + 1))
        return
    fi
    if [ -d "$src" ]; then
        rm -rf "$dst"
        cp -r "$src" "$dst"
        echo "  ✓ $rel" | sed 's/^/  /'
    else
        cp "$src" "$dst"
        echo "  ✓ $rel" | sed 's/^/  /'
    fi
}

echo "→ local manifest"
mkdir -p "$TREE/.repo/local_manifests"
cp "$HERE/.repo/local_manifests/zeus.xml" "$TREE/.repo/local_manifests/"
echo "  ✓ .repo/local_manifests/zeus.xml"

if [ ! -d "$TREE/device/xiaomi/zeus" ]; then
    echo
    echo "… 设备树还没拉下来，先跑："
    echo
    echo "    cd $TREE"
    echo "    repo sync -c -j8"
    echo
    echo "  完事再跑一次 bash apply.sh，把剩下的文件覆盖进去。"
    exit 0
fi

echo
echo "→ device/xiaomi/zeus"
put device/xiaomi/zeus/infinity_zeus.mk   "IX manifest"
put device/xiaomi/zeus/AndroidProducts.mk "IX manifest"
put device/xiaomi/zeus/stubs_defaults      "IX manifest"

echo
echo "→ device/xiaomi/sm8450-common"
put device/xiaomi/sm8450-common/common.mk "IX manifest"

echo
echo "→ hardware/xiaomi"
put hardware/xiaomi/Android.bp "IX manifest"

echo
echo "→ vendor/infinity"
put vendor/infinity/config/version.mk "IX manifest"

if [ "$MISSING" -gt 0 ]; then
    echo
    echo "✗ 有 $MISSING 处没覆盖上，原因是仓库没 sync 完。"
    echo "  跑完整的 repo sync -c -j8，再跑一次本脚本。"
    exit 1
fi

echo
echo "✓ 全部覆盖完成。"
echo
echo "  核对一下（每条都该有输出）："
echo
echo "    cd $TREE"
echo "    git -C device/xiaomi/zeus status --short          # 3 项"
echo "    git -C device/xiaomi/sm8450-common status --short # M common.mk"
echo "    git -C hardware/xiaomi status --short             # M Android.bp"
echo "    git -C vendor/infinity status --short             # M config/version.mk"
echo
echo "  然后编译："
echo
echo "    source build/envsetup.sh"
echo "    lunch infinity_zeus-userdebug"
echo "    mka bacon -j8"
