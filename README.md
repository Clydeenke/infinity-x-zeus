# Xiaomi 12 Pro (zeus) — Infinity X 3.12

Android 16 / LineageOS 23.2 / Infinity X

非官方构建。与小米、LineageOS、Project Infinity X 官方均无关联，不代表
任何一方的立场。

## 编译

```bash
# 1. 拿这个仓库，apply.sh 和 manifest/zeus.xml 都在里面
cd ~
git clone https://github.com/Clydeenke/infinity-x-zeus.git

# 2. 建源码树
mkdir -p ~/android && cd ~/android
repo init -u https://github.com/ProjectInfinity-X/manifest -b 16

# 3. apply.sh 在源码树里跑，它自己会认出位置
RECIPE=~/infinity-x-zeus        # 上一条 clone 出来的目录

bash $RECIPE/apply.sh           # 第一次：放 local manifest（sync 前）
repo sync -c -j8
bash $RECIPE/apply.sh           # 第二次：覆盖设备树文件（sync 后）

# 4. 编译
source build/envsetup.sh
lunch infinity_zeus-user        # 正式版；调试版用 infinity_zeus-userdebug
mka bacon -j8
```

`apply.sh` 跑两次：第一次只放 local manifest（sync 前），第二次把设备树文件
覆盖进去（sync 后）。可以重复跑。

产物在 `out/target/product/zeus/`。

环境：`-j8`，内存 30G 以上。

磁盘要留 **350G**。实测占用：

| | |
|---|---|
| `repo sync` 完的源码树 | 约 175G |
| `out/` 编译产物 | 约 150G |
| 合计 | 约 325G |

`manifest/zeus.xml` 里用 `<remove-project>` 去掉了 emulator、qemu-kernel、cts，
`repo sync` 时自动不拉，省约 53G。所以**不需要手动删任何东西**，照上面跑就行。
`out/` 可以随时删，删了再编就是慢一点。

## apply.sh 覆盖了什么

这 6 个文件是让 IX 能编 zeus 必需的改动：

| 文件 | 改什么 |
|---|---|
| `overlays/device/xiaomi/zeus/infinity_zeus.mk` | 新增。产品定义，原本只有 `lineage_zeus.mk` |
| `overlays/device/xiaomi/zeus/AndroidProducts.mk` | 4 行。`PRODUCT_MAKEFILES` 指向 `infinity_zeus.mk`，加 `COMMON_LUNCH_CHOICES` |
| `overlays/device/xiaomi/zeus/stubs_defaults/` | 新增。`cts/` 被删之后全树找不到的 defaults 补在这 |
| `overlays/device/xiaomi/sm8450-common/common.mk` | 3 行。Soong namespace 加 wlan / qcwcn / trusty |
| `overlays/hardware/xiaomi/Android.bp` | 1 行。`soong_namespace` 加 `imports: ["device/xiaomi/zeus"]` |
| `overlays/vendor/infinity/config/version.mk` | 1 行。`INFINITY_MAINTAINER` |

两个新增文件（`infinity_zeus.mk`、`stubs_defaults/`）不存在冲突问题：上游本来
就没有这两个东西。剩下 4 个是**整文件覆盖既有文件**，上游改了同一个文件时会被
我们盖回去，所以更新时必须看 diff，见下面「更新」。

vendor blobs 一个字节没改。

覆盖完自己核对：

```bash
git -C device/xiaomi/zeus status --short          # 应有 3 项
git -C device/xiaomi/sm8450-common status --short # 应只有 M common.mk
git -C hardware/xiaomi status --short             # 应只有 M Android.bp
git -C vendor/infinity status --short             # 应只有 M config/version.mk
```

## 为什么 local_manifest 钉 commit 不跟分支

那 9 个项目在本仓库的 `manifest/zeus.xml` 里都钉在具体 commit 上，不写分支名。
`apply.sh` 会把它复制到源码树的 `.repo/local_manifests/zeus.xml`，那是 repo 读的
位置。

原因：`sm8450-common` 的 `lineage-23.2` 在 2026-09 之后多了 34 个提交，其中 3 个
删掉了 `overlay/DialerResXiaomi`、`overlay/WifiResTarget`、
`overlay/WifiResTarget_cape` 三个目录，同时从 `common.mk` 里删掉对应的
`PRODUCT_PACKAGES` 行。

跟着分支走会拿到新版目录状态，再用旧版 `common.mk` 覆盖回去，就变成引用不存在的
目录，构建直接失败。钉 commit 才能保证 overlays 盖得上。

commit 哈希基本不会"过期"——GitHub 上的对象不会自动消失。唯一的例外是上游
删库或用 force push 改写历史，那就拉不到了，得换成新的 commit。

两个 XML 写法上的坑：

- `vendor/infinity` 本身是 IX manifest 里的项目。要在 local manifest 里钉它，
  必须**先 `<remove-project name="vendor_infinity" />` 再重新 `<project>`**。
  只改 `name` 或 `remote` 会被 repo 判成两个项目占同一路径，报
  `duplicate path`，整个 sync 起不来。
- `kernel/xiaomi/sm8450` 的 9 个项目 remote 名是 `github`，`vendor/infinity` 是
  `infinity`，不是 `origin`。

## 更新

### 1. 看有没有新提交

在源码树里跑，`RECIPE` 还是上面那个路径：

```bash
bash $RECIPE/check-updates.sh
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

# 把本仓库 manifest/zeus.xml 里那个项目的 revision 换成它，
# 然后 bash $RECIPE/apply.sh 把它带进树里
```

### 4. 同步、覆盖、编译

```bash
repo sync -c -j8 device/xiaomi/sm8450-common
bash $RECIPE/apply.sh
source build/envsetup.sh
lunch infinity_zeus-user
mka bacon -j8
```

编出来确认功能正常，再 commit 改过的 `manifest/zeus.xml` 和 `overlays/`。

### 升 Android 大版本

比如升到 Android 17，local manifest 里那 9 个 pin 全要换，而且要求
`LineageOS/android_device_xiaomi_zeus` 等仓库先有对应版本分支。没有分支就是
无树可编，只能等官方发出来。

`repo init` 的 `-b 16` 也要跟着改成 IX 对应新版本的分支名。

## 验证到哪一步

已核对（实测）：

- 全量 `mka bacon` 跑通，`user` 变体，`release-keys` 签名，退出码 0
- 编出来的 zip 已刷进 Xiaomi 12 Pro，开机进系统正常
- 刷后实测：相机、指纹、NFC、充电、信号都正常
- local manifest 里 9 个项目按 commit 拉到，8 个 SHA 命中（`kernel/xiaomi/sm8450`
  未实测拉取，commit 取自作者编译成功的那棵源码树）
- `apply.sh` 覆盖后的文件与作者编译成功那棵源码树的对应文件**逐字节一致**
- XML 合法，manifest 合并无冲突（`vendor/infinity` 的 remove + 重加写法已实测）
- `apply.sh` 可重复执行，仓库没 sync 完时会明确报出缺哪个
- `check-updates.sh` 在真实源码树上跑过

没验证的：上面列的几项之外的功能没测。刷之前按官方 LineageOS 教程做备份，
出问题自己负责。

编译出错请开 issue，附上日志里 `FAILED:` 那几行，和
`cat .repo/local_manifests/zeus.xml` 的内容。

## Credits

- [Project Infinity X](https://github.com/ProjectInfinity-X)
- [LineageOS](https://lineageos.org)
- [TheMuppets](https://github.com/TheMuppets) — vendor blobs
- [tejas101k](https://gitlab.com/tejas101k/vendor_google_gms) — GApps vendor
