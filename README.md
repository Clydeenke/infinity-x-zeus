# Xiaomi 12 Pro (zeus) — Infinity X 3.12

Android 16 / LineageOS 23.2 / Infinity X

## 编译

```bash
repo init -u https://github.com/ProjectInfinity-X/manifest -b 16

bash apply.sh
repo sync -c -j8
bash apply.sh

source build/envsetup.sh
lunch infinity_zeus-userdebug
mka bacon -j8
```

`apply.sh` 跑两次：第一次放 local manifest（sync 前），第二次把设备树文件
覆盖进去（sync 后）。可以重复跑。

正式版在 `lunch` 之后加一行：

```bash
export TARGET_BUILD_VARIANT=user
```

产物在 `out/target/product/zeus/`。

环境：`-j8`，内存 30G 以上，源码树所在分区留 40G 以上。`out/` 可以随时删。

## apply.sh 覆盖了什么

这 5 个文件是让 IX 能编 zeus
必需的改动：

| 文件 | 改什么 |
|---|---|
| `overlays/device/xiaomi/zeus/infinity_zeus.mk` | 新增。产品定义，原本只有 `lineage_zeus.mk` |
| `overlays/device/xiaomi/zeus/AndroidProducts.mk` | 4 行。`PRODUCT_MAKEFILES` 指向 `infinity_zeus.mk`，加 `COMMON_LUNCH_CHOICES` |
| `overlays/device/xiaomi/zeus/stubs_defaults/` | 新增。`cts/` 被删之后全树找不到的 defaults 补在这 |
| `overlays/device/xiaomi/sm8450-common/common.mk` | 3 行。Soong namespace 加 wlan / qcwcn / trusty |
| `overlays/hardware/xiaomi/Android.bp` | 1 行。`soong_namespace` 加 `imports: ["device/xiaomi/zeus"]` |
| `overlays/vendor/infinity/config/version.mk` | 1 行。`INFINITY_MAINTAINER` |

前 3 个里的新增文件不存在冲突问题。后 3 个是**整文件覆盖既有文件**，上游改了
同一个文件时会被盖回去，见下面「更新」。

vendor blobs 一个字节没改。

覆盖完自己核对：

```bash
git -C device/xiaomi/zeus status --short          # 应有 3 项
git -C device/xiaomi/sm8450-common status --short # 应只有 M common.mk
git -C hardware/xiaomi status --short             # 应只有 M Android.bp
git -C vendor/infinity status --short             # 应只有 M config/version.mk
```

## 为什么 local_manifest 钉 commit 不跟分支

那 9 个项目在 `.repo/local_manifests/zeus.xml` 里都钉在具体 commit 上，不写
分支名。

原因：`sm8450-common` 的 `lineage-23.2` 在 2026-09 之后多了 34 个提交，其中 3 个
删掉了 `overlay/DialerResXiaomi`、`overlay/WifiResTarget`、
`overlay/WifiResTarget_cape` 三个目录，同时从 `common.mk` 里删掉对应的
`PRODUCT_PACKAGES` 行。

跟着分支走会拿到新版目录状态，再用旧版 `common.mk` 覆盖回去，就变成引用不存在的
目录，构建直接失败。钉 commit 才能保证 overlays 盖得上。

commit 哈希是 GitHub 上永久存在的地址，所以钉死不会"过期"。

两个 XML 写法上的坑：

- `vendor/infinity` 本身是 IX manifest 里的项目。要在 local manifest 里钉它，
  必须**先 `<remove-project name="vendor_infinity" />` 再重新 `<project>`**。
  只改 `name` 或 `remote` 会被 repo 判成两个项目占同一路径，报
  `duplicate path`，整个 sync 起不来。
- `kernel/xiaomi/sm8450` 的 9 个项目 remote 名是 `github`，`vendor/infinity` 是
  `infinity`，不是 `origin`。

## 更新

### 1. 看有没有新提交

```bash
bash check-updates.sh
```

只 fetch，不动工作区。输出形如：

```
  ✓ device/xiaomi/zeus                 lineage-23.2     已是最新
  ↑ device/xiaomi/sm8450-common        lineage-23.2     落后 34  ⚠ 覆盖的 common.mk 上游改了
  ↑ hardware/xiaomi                    lineage-23.2     落后 1   · 覆盖的 Android.bp 没动，可直接换
```

- `落后 0` = 不用管
- `· 覆盖的 X 没动` = 可以直接换 pin，不用改 overlays
- `⚠ 覆盖的 X 上游改了` = 必须先看 diff，见下一步

### 2. 看覆盖文件被改成什么样

```bash
git -C device/xiaomi/sm8450-common diff \
    ffe9fc07b5ec4c5d3276897a49a4e9fdde9a4a62..refs/remotes/upstream-check/lineage-23.2 \
    -- common.mk
```

判断三件事：我们的那几行还在不在、位置变没变、上游有没有删掉我们引用的目录。

如果上游删了我们引用的目录（2026-09 那次就是），整文件盖回去就是构建失败。
这时候要把我们的改动挪到新版文件的对应位置，改 `overlays/` 里的文件，
再继续第 3 步。

### 3. 换 pin

```bash
# 取新 commit 哈希
git -C device/xiaomi/sm8450-common rev-parse refs/remotes/upstream-check/lineage-23.2

# 把 zeus.xml 里那个项目的 revision 换成它
```

### 4. 同步、覆盖、编译

```bash
repo sync -c -j8 device/xiaomi/sm8450-common
bash apply.sh
source build/envsetup.sh
lunch infinity_zeus-userdebug
mka bacon -j8
```

编出来确认功能正常，再 commit 改过的 `zeus.xml` 和 `overlays/`。

### 升 Android 大版本

比如升到 Android 17，local manifest 里那 9 个 pin 全要换，而且要求
`LineageOS/android_device_xiaomi_zeus` 等仓库先有对应版本分支。没有分支就是
无树可编，只能等官方发出来。

`repo init` 的 `-b 16` 也要跟着改成 IX 对应新版本的分支名。

## 验证到哪一步

已核对（实测）：

- local manifest 里 8 个项目按 commit 拉到，SHA 全部命中（`kernel/xiaomi/sm8450`
  未实测拉取，commit 取自产出本包的那棵树）
- `apply.sh` 覆盖后的文件与产出本包那棵树的对应文件**逐字节一致**
- XML 合法，manifest 合并无冲突（`vendor/infinity` 的 remove + 重加写法已实测）
- `apply.sh` 可重复执行，仓库没 sync 完时会明确报出缺哪个
- `check-updates.sh` 在真实源码树上跑过

未做：未从零完成全量 `mka bacon`（受磁盘和时长限制没跑得下来）。

编译出错请开 issue，附上日志里 `FAILED:` 那几行和 `repo sync` 后的
`.repo/manifest.xml` 里 zeus 那几行。

## Credits

- [Project Infinity X](https://github.com/ProjectInfinity-X)
- [LineageOS](https://lineageos.org)
- [TheMuppets](https://github.com/TheMuppets) — vendor blobs
- [tejas101k](https://gitlab.com/tejas101k/vendor_google_gms) — GApps vendor
