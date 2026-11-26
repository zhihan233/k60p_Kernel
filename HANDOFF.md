# HANDOFF（2026-11-26 09:15 暂停，12:00 继续）— 转向 LineageOS 内核基线

## 一句话状态
ACK/GKI 路线已被证明走不通（v4 临时启动后**扬声器、摄像头失效**，用户已刷回官方 boot）。
已按用户决定**改用 LineageOS 内核基线**（与官方 vendor 模块同属 QCOM msm-kernel 血统），
新流水线目录 `los/` 已搭了一半（配置/补丁/工具脚本已就位），**还差 3 个构建脚本 + workflow**，
中午继续写完并触发云端构建。

## 关键事实（已从官方内核/设备实测确认）
- 官方内核 banner 是**伪装的 GKI 版本串**：实际是小米自己的树在 **2026-04-15** 用
  **Android clang 14.0.7 (r450784e)** 编的（`/proc/version`: build-user@build-host）。
- 官方 boot 下：**402 个模块全部加载、`disagrees about version` = 0** → 官方内核 CRC 与模块完全匹配。
- 设备 ROM 是**官方 HyperOS 3.0.304.0.WMKCNXM**，但 **vendor 分区指纹是 Android 13**
  （`TKQ1.221114.001 / OS3.0.304.0.WMKCNXM`）→ vendor 模块来自 Android 13 的 **5.15.78** vendor 树。
- 扫描 `/vendor_dlkm/lib/modules/*.ko`（291 个文件）：**vermagic 全部 = 5.15.78**。
- 公开源码 `MiCode/Xiaomi_Kernel_OpenSource` 分支 `socrates-t-oss` **只有 5.15.41**
  （ACK_SHA b13f29a9），和机器上的 5.15.78 对不上 → 无法复现官方内核。
- 我们的 ACK 5.15.194 内核（v4）在设备上：402 模块能加载（兼容模式），但
  **扬声器/摄像头坏**（ABI/结构体/回调不兼容），证实“跳过 CRC 加载”不可靠。
- 用户已刷回官方 boot，扬声器/摄像头恢复。

## 为什么用 LineageOS 内核（已验证的先例）
本地 `research/prior/clones/K60Prosocrates-Kernel-DroidSpaces`（shark-wan 项目）是
**实机验证成功**的配方：
- 源码：`LineageOS/android_kernel_xiaomi_sm8550` 分支 `lineage-23.2`，
  commit `093e3da978e7b954d041a261d40975957c7fe6f1`，release `5.15.211-g093e3da978e7`
- 工具链：AOSP clang **r563880c**（21.0.0），**Full LTO + CFI + MTE/KASAN + MODVERSIONS 全保留**
- 结果：**ABI 0 mismatch**（3971 个可比导入符号全匹配）、实机启动成功、402 模块正常、
  Droidspaces 需求全过、SukiSU LKM root 正常
- 它的脚本/配置/证据可直接复用（已拷贝进 `los/`）

## `los/` 目录当前进度
已就位：
- `los/config/device-baseline.config` —— LOS 设备基线 config（221KB，从 shark-wan 克隆拷贝）
- `los/config/droidspaces.config` —— Droidspaces GKI 配置清单
- `los/config/extras.config` —— 额外游戏优化（LRU_GEN_ENABLED / fq_codel 默认 / BBR / ECN）
- `los/config/sources.lock.json` —— LOS 源码 commit + sha + clang r563880c + BBG + AnyKernel3 + release 标签 `k60p-kernel-los-v1`
- `los/config/anykernel.sh` —— AK3 配置（BLOCK=boot / IS_SLOT_DEVICE=1）
- `los/patches/` —— 0001 sysvipc kABI、0010 BBG、0020~0024 游戏小补丁
- `los/evidence/vendor-module-versions.json` —— 原厂模块导入符号 CRC 证据（1.5MB）
- `los/scripts/` —— prepare-runner.sh、check_module_abi.py、elf_versions.py、
  verify_git_tree.py、make_bootimg.py（已完成）
**待写**：`los/scripts/prepare.sh`、`los/scripts/build.sh`、`los/scripts/package.sh`、
`los/scripts/publish.sh`，以及 `.github/workflows/build-los.yml`

## 12:00 继续步骤（按顺序）
1. 写 `los/scripts/prepare.sh`：
   - 读 `los/config/sources.lock.json`；下载 LOS 源码 tarball（codeload，sha256 校验，
     `--strip-components=1` 解到 `los/kernel/`）
   - 下载 clang r563880c（Gitiles archive）→ 解压 `los/toolchain/clang-r563880c/` →
     `verify_git_tree.py` + Gitiles tree JSON 校验 + `clang --version`
   - 打补丁：`0001-sysvipc`（`--fuzz=0`，LOS 树实测可干净应用）；
     `0010-baseband-guard`（`--fuzz=3`，硬失败则停止）；`0020~0024`（逐个 `--fuzz=3`，
     失败则记入 `dist/patches-skipped.txt` 继续）
   - `printf '%s\n' '-g093e3da978e7' > los/kernel/.scmversion`
   - 保存 sched.h/gki_defconfig 原始副本 + diff 成 `dist/source.patch`
2. 写 `los/scripts/build.sh`：
   - 导出 PATH/ARCH/LLVM=1/CROSS_COMPILE；`JOBS=nproc`；`timeout 4200 make`
   - `cp los/config/device-baseline.config los/out/.config`
   - 把 `droidspaces.config` 与 `extras.config` 的 `CONFIG_X=y` 同时写进
     `kernel/arch/arm64/configs/gki_defconfig` 和 `out/.config`
   - **BBG**：确保 `CONFIG_LSM` 含 `baseband_guard`（读当前值后插入，写回两份 config）
   - `make olddefconfig` → diffconfig → 自检：
     * 硬约束：MODVERSIONS / CFI_CLANG / LTO_CLANG_FULL / KASAN_HW_TAGS /
       SHADOW_CALL_STACK / DEBUG_INFO_BTF / MODULE_SIG_PROTECT / TARGET_PRODUCT_SOCRATES
       必须与基线一致且 =y；CFS_BANDWIDTH/CGROUP_PIDS 与基线一致
     * Droidspaces 清单全部 y；BBG=y 且 LSM 含 baseband_guard
     * extras 缺失只告警（olddefconfig 可能丢弃树里不存在的符号）
   - `make -C kernel O=out -j$JOBS Image modules | tee dist/build.log`
   - 复制 Image / Module.symvers / utsrelease.h / .config 到 dist/（命名 `*-los`）
   - 断言 UTS_RELEASE == lock release（`5.15.211-g093e3da978e7`）
   - `python3 scripts/check_module_abi.py dist/Module.symvers evidence/vendor-module-versions.json
     --report dist/abi-report-los.json`；**期望 mismatch=0**（不是 0 就记录并告警，
     先不阻塞，但要把差异写进 HANDOFF）
   - 写 `dist/build-los.json` / `dist/status-los.txt`
3. 写 `los/scripts/package.sh`：
   - `python3 scripts/make_bootimg.py --kernel dist/Image-los --output dist/boot-los.img`
     （header v4，kernel 偏移 4096，无 ramdisk；与之前 v3/v4 实测可启动的格式一致）
   - 拉 AnyKernel3（pinned commit）→ 拷 `dist/Image-los` + `config/anykernel.sh` +
     `build-los.json` → zip 成 `dist/ak3-los.zip`
   - SHA256SUMS-los + RELEASE-los.md（功能、刷入、回滚、自检、来源说明）
4. 写 `.github/workflows/build-los.yml`：
   - 触发：push paths `los/**`、workflow 自身
   - 步骤：checkout → `bash los/scripts/prepare-runner.sh` → 恢复/保存 clang r563880c 缓存
     （key `aosp-clang-r563880c-571ed3e20b5708cea1177d5072853fc5b85b6877`）→
     `bash los/scripts/prepare.sh` → 分配 swap（同旧 workflow 逻辑）→
     `bash los/scripts/build.sh` → `bash los/scripts/package.sh` →
     用 `GH_TOKEN=${{ github.token }}` 上传到 Release `k60p-kernel-los-v1`（`--clobber`）→
     upload-artifact
   - `permissions: contents: write`，timeout 150min
5. 本地 `bash -n` 全部脚本 + yaml 校验 → commit & push（`los/**` 不在旧 ACK workflow 的
   paths 里，不会误触发 ACK 构建）
6. 等构建（LOS 树 Full LTO 约 30-50 分钟；若 OOM/超时，把 `CONFIG_LTO_CLANG_FULL` 换成
   `CONFIG_LTO_CLANG_THIN` 重试，ThinLTO 不影响 CRC/CFI 兼容性）
7. 下载 `boot-los.img` + `ak3-los.zip` + `abi-report-los.json`，本地校验 boot header/版本串
   （用 `work/verify_v3_final.py` 改文件名，或 `work/check_gaming_img.py` 思路）
8. 让用户 `fastboot boot boot-los.img` 测试（**先别 flash**）：重点
   扬声器、摄像头、WiFi、充电、BBG、Droidspaces requirements、KernelSU root
   - 同时 `adb shell su -c "lsmod | wc -l"` 应为 402，`dmesg | grep -i E 'disagrees|CFI failure'` 应为空
9. 验证通过后再做 gaming 变体（可加 BBRv3/调度补丁）与正式 flash 建议

## 注意/坑
- GitHub 未认证 API 限额常满；用 HTML actions 页 + `raw.githubusercontent.com` +
  `git ls-remote`。本地 `parse_actions.py` 在 `work/`。
- 本地 git push 直连 SSH 可用（代理没开时）：`git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push`
- adb：`R:\platform-tools\adb.exe`；设备当前官方内核、USB 调试已开（如 offline 执行
  `adb kill-server && adb start-server && adb reconnect offline`）
- 旧 ACK 流水线文件（`scripts/`、`config/`、`patches/`、`build.yml`）保留但先不要动，
  免得误触发 ACK 构建；LOS 工作全在 `los/` 下
- ACK 的 v19 stockref 实验（r450784e 工具链）因工具链下载脚本 bug 失败，已无必要继续
- 参考克隆：`research/prior/clones/K60Prosocrates-Kernel-DroidSpaces/`（脚本可对照）
- 用户沟通要点：官方 HyperOS 3.0.304 是“Android 16 system + Android 13 vendor”的官方包；
  版本串不必和原厂一样（带 CRC 的模块会忽略 release），但**结构体/回调 ABI 必须同源**
