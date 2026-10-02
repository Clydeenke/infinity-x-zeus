#!/usr/bin/env bash
#
# 看 local_manifest 里那 9 个项目上游有没有新提交，以及我们整文件覆盖的
# 文件有没有被上游改过。
#
#   bash check-updates.sh
#   TREE=~/android bash check-updates.sh
#
# 只 fetch，不动工作区，不改任何本地文件。fetch 下来的分支存在
# refs/remotes/upstream-check/，之后可以拿它看 diff。
#
# 每个项目只认一个分支：包含你 pin 的那个分支里、离你最近的那个。
# lineage-22.2 这种老分支不算，那不是"可更新"。
#
set -uo pipefail

TREE="${TREE:-$PWD}"

# 路径 | 我们整文件覆盖掉的既有文件（留空 = 只新增文件，永远不会冲突）
PROJECTS=(
  "device/xiaomi/zeus|AndroidProducts.mk"
  "device/xiaomi/sm8450-common|common.mk"
  "hardware/xiaomi|Android.bp"
  "vendor/infinity|config/version.mk"
  "kernel/xiaomi/sm8450|"
  "kernel/xiaomi/sm8450-devicetrees|"
  "kernel/xiaomi/sm8450-modules|"
  "vendor/xiaomi/zeus|"
  "vendor/xiaomi/sm8450-common|"
)

[ -d "$TREE/.repo" ] || { echo "✗ $TREE 下没有 .repo" >&2; exit 1; }

STALE=0
STAY=0
UP=0

for entry in "${PROJECTS[@]}"; do
    path="${entry%%|*}"
    covered="${entry##*|}"
    dir="$TREE/$path"

    if [ ! -e "$dir/.git" ]; then
        printf "  ⬜ %-34s 没 sync\n" "$path"
        continue
    fi

    rem=$(git -C "$dir" remote 2>/dev/null | head -1)
    if [ -z "$rem" ]; then
        printf "  ⬜ %-34s 读不到 remote\n" "$path"
        continue
    fi

    if ! git -C "$dir" fetch --quiet "$rem" "+refs/heads/*:refs/remotes/upstream-check/*" 2>/dev/null; then
        printf "  ⬜ %-34s fetch 失败（网络？）\n" "$path"
        continue
    fi

    pin=$(git -C "$dir" rev-parse HEAD)

    # 找包含 pin 的分支里最贴近的那个
    best=""; bestn=-1
    for br in $(git -C "$dir" for-each-ref --format='%(refname:strip=3)' refs/remotes/upstream-check/ 2>/dev/null); do
        git -C "$dir" merge-base --is-ancestor "$pin" "refs/remotes/upstream-check/$br" 2>/dev/null || continue
        n=$(git -C "$dir" rev-list --count "$pin..refs/remotes/upstream-check/$br" 2>/dev/null) || continue
        if [ "$bestn" -lt 0 ] || [ "$n" -lt "$bestn" ]; then best="$br"; bestn="$n"; fi
    done

    if [ -z "$best" ]; then
        printf "  ? %-34s pin %s 不在任何分支上\n" "$path" "${pin:0:12}"
        continue
    fi

    if [ "$bestn" = "0" ]; then
        printf "  ✓ %-34s %-16s 已是最新\n" "$path" "$best"
        STAY=$((STAY+1))
        continue
    fi

    ref="refs/remotes/upstream-check/$best"
    note=""
    if [ -n "$covered" ]; then
        d=$(git -C "$dir" diff --stat "$pin..$ref" -- "$covered" 2>/dev/null | tail -1)
        if [ -n "$d" ]; then
            note="⚠ 覆盖的 $covered 上游改了"
            STALE=$((STALE+1))
        else
            note="· 覆盖的 $covered 没动，可直接换"
        fi
    else
        note="· 只新增文件，无冲突，可直接换"
    fi

    printf "  ↑ %-34s %-16s 落后 %-3s %s\n" "$path" "$best" "$bestn" "$note"
    git -C "$dir" log --oneline "$pin..$ref" 2>/dev/null | head -5 | sed 's/^/        /'
    UP=$((UP+1))
done

echo
echo "──────────────────────────────"
echo "最新 $STAY 个，有更新 $UP 个，其中 $STALE 个的覆盖文件被上游改过。"
echo
if [ "$UP" -gt 0 ]; then
cat <<'EOF'
换 pin 的步骤

  1. 先看覆盖文件到底被改成什么样（把 <树> 换成你的源码树路径）：

       git -C <树>/device/xiaomi/sm8450-common diff \
           <旧pin>..refs/remotes/upstream-check/<分支> -- common.mk

     标了 ⚠ 的必须看。看完判断：我们的那几行还在不在？位置变没变？
     如果上游删掉了我们引用的目录（就像 2026-09 那次删 overlay 目录那样），
     整文件盖回去就是构建失败，这种情况下要把我们的改动挪到新版
     common.mk 的对应位置，再更新 overlays/ 里的文件。

  2. 把本仓库 manifest/zeus.xml 里那个项目的 revision 换成
     refs/remotes/upstream-check/<分支> 的 commit 哈希：

       git -C <树>/<项目> rev-parse refs/remotes/upstream-check/<分支>

     改完 bash apply.sh 把它带进树里。

  3. 同步 + 重新覆盖 + 编译：

       repo sync -c -j8 <项目路径>
       bash apply.sh
       source build/envsetup.sh && lunch infinity_zeus-user
       mka bacon -j8

  4. 编出来确认功能正常之后，再 commit 改 manifest/zeus.xml 和 overlays/。

升 Android 大版本（比如 17）时，local_manifest 里那 9 个 pin 全都要换，
而且 LineageOS 那边要先有对应分支。没有分支就是无树可编，只能等。
EOF
fi
