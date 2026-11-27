# 交接文档 — Redmi K60 Pro (socrates) LineageOS 5.15 定制内核

| 项目 | 内容 |
|---|---|
| 文档版本 | v1.3（正式交接版；2026-11-27 许可证改 MIT、重建 run 6、关闭 push 自动构建） |
| 生成日期 | 2026-11-26（v1.0）/ 2026-11-27（v1.1 MIT、v1.2 重建与哈希、v1.3 手动构建） |
| 项目状态 | ✅ 已交付：构建成功、真机验证通过、**已永久刷入设备** |
| 交付方 | deepseek v4.1flash |
| 接收方 | 后续维护者 / 接手 agent |
| 仓库 | https://github.com/zhihan233/k60p_Kernel |
| 本地工作区 | `D:\Administrator\Documents\ai\k60p_build`（Windows） |
| 目标设备 | Redmi K60 Pro（`socrates` / SM8550），HyperOS 3.0.304.0.WMKCNXM（Android 16） |

---

## 0. 交接摘要（先读这段）

- **内核**：基于 LineageOS `android_kernel_xiaomi_sm8550`（`lineage-23.2` @ `093e3da978e7`），Linux **5.15.211**，
  版本串 `5.15.211-g093e3da978e7`；clang r563880c（21.0.0）编译，**ThinLTO + CFI + MODVERSIONS + KASAN_HW_TAGS**。
- **ABI 核心结论**：与官方 vendor 模块 **0 个 CRC 差异**——401 个模块（400 个原厂 vendor 模块 + KernelSU 的 `kernelsu`）
  全部加载、0 加载失败。这是扬声器 / 摄像头等厂商驱动能正常工作的根本原因。
- **交付物**：Release `k60p-kernel-los-v1`（`boot-los.img` / `ak3-los.zip` / `Image-los` / ABI 报告 / 构建元数据 / 内核配置）；
  本地 `deliver/`（gitignore）另存原厂 boot 备份 `stock-boot_a.img`，用于回滚。
- **实机状态**：2026-11-26 19:10–19:15 在 `fastboot boot` 临时启动下完成全部验收（用户确认扬声器/麦克风/摄像头正常，
  agent 完成终端内测试）；**2026-11-26 20:52 复核 `boot_a` 前 43,315,200 字节 sha256 = run 4 构建的 `bf6db3cc…`，
  确认设备已永久刷入本内核**，当前运行 `uname -r = 5.15.211-g093e3da978e7`。
- **Release 与设备镜像**：Release 资产已于 **2026-11-27 因许可证改 MIT 重建（run 6）**，与设备运行的 run 4 镜像
  **源码/ABI 相同、二进制哈希不同**（构建非字节可复现，见 §2.1 / §8）。
- **唯一必须知道的差异**：版本串与官方不同是**预期行为**（模块带 `__versions`，vermagic 比对忽略 release 段）；
  `boot.img` 不带原厂 AVB 签名，需保持 Bootloader 解锁；系统 OTA 前应先刷回原厂 boot。
- **日常维护**：重建需**手动触发** GitHub Actions（Actions → build-los → Run workflow，约 18–20 分钟），成功后自动发布 Release；
  push 不会自动构建（2026-11-27 起，避免误触发重建/覆盖 Release）。

---

## 1. 原始需求与完成情况

| 原始需求 | 实现方式 | 状态 |
|---|---|---|
| 5.15 最新内核 | LineageOS sm8550 `lineage-23.2`（Linux 5.15.211） | ✅ |
| Droidspaces 内核要求 | GKI 5.15 官方配置 + SYSVIPC kABI padding（task_struct 槽 6/7/8）补丁 | ✅ |
| BBG 防格机 | Baseband-guard LSM（`CONFIG_BBG=y`，LSM 顺序中含 `baseband_guard`） | ✅ 实测拦截 |
| 针对游戏优化 | MGLRU 默认开启、fq_codel 默认队列、BBR、CAKE/FQ/FQ_CODEL、调度/内存/定时器小补丁 | ✅ |
| GitHub 云端编译 | `.github/workflows/build-los.yml`（push 触发，ThinLTO） | ✅ 20m31s |
| 驱动可用（不换官方驱动） | 用与官方同源的 LineageOS vendor 树内核，ABI 0 CRC 差异 | ✅ 扬声器/摄像头正常 |
| CRC / 版本不静默 | 不采用"忽略 CRC"补丁；加载失败时内核默认拒绝并打印 `disagrees about version`；构建期产出 ABI 报告 | ✅ |

> 原始背景：官方 HyperOS 内核是小米用自家 **5.15.78 vendor 树**（clang r450784e）编译并伪装成 GKI 版本串
> `5.15.194-android13-8-00019-gf4321180a397-ab15212794`；公开源码 MiCode `socrates-t-oss` 只有 5.15.41，
> 因此用 Android Common Kernel 无法复现官方 ABI。

---

## 2. 交付物清单

### 2.1 Release 资产（`k60p-kernel-los-v1`）

Release：https://github.com/zhihan233/k60p_Kernel/releases/tag/k60p-kernel-los-v1

> 当前资产来自 **run 6**（2026-11-27 许可证调整后重建，commit `12c2b6c`）。
> ⚠️ **构建非字节可复现**：同一源码多次 CI 构建的 Image/boot 哈希不同（实测 run 4 / 5 / 6 各不相同），
> 请以 Release 内 `SHA256SUMS-los` 为准；ABI 一致性以 `abi-report-los.json` 为准，不要跨构建比对哈希。

| 文件 | 大小 | SHA-256 | 说明 |
|---|---|---|---|
| `boot-los.img` | 43,315,200 B | `5c42d8a830d312a6c2bee093ca836c57fd36a27f5efd646bbd7cfd768d9868be` | fastboot 用 boot 镜像（header v4，kernel 偏移 4096，无 ramdisk） |
| `ak3-los.zip` | 22,598,024 B | `00030917613289503b0c4f6c08fb5fd4c6768ded00fd2f24df8459f33fa64745` | AnyKernel3 刷机包（`BLOCK=boot`，A/B；内含 AK3 `LICENSE` + 本仓库 `LICENSE.k60p-kernel.txt`） |
| `Image-los` | 43,309,568 B | `84d680966ecf4e1e5cfdf699820d5fe52481b35606e5f839a7e58eab37485221` | 裸 arm64 Image |
| `SHA256SUMS-los` | 233 B | — | 上述三个文件的校验值 |
| `abi-report-los.json` | 18,858 B | — | 厂商模块 ABI 对比报告（`crc_mismatches=0`） |
| `build-los.json` | 2,731 B | — | 构建元数据（内核/工具链/版本/ABI/哈希） |
| `kernel-los.config` | 223,041 B | — | 最终内核配置 |

> Release 说明正文只在**首次创建时**生成（run 4），后续重建不会更新正文；许可信息以包内 LICENSE 文件为准。

### 2.2 本地 `deliver/`（gitignore，不在仓库内）

| 文件 | 大小 | 说明 |
|---|---|---|
| `boot-los.img` / `ak3-los.zip` / `Image-los` / `SHA256SUMS-los` / `abi-report-los.json` / `build-los.json` / `kernel-los.config` | run 4 构建 | 本地产物缓存（**run 4 产物 = 设备当前已刷入的版本**：boot `bf6db3cc…`、Image `865c9800…`、ak3 `b1819b07…`；Release 已重建为 run 6，见 §2.1） |
| `stock-boot_a.img` | 201,326,592 B（192 MiB 分区镜像） | **原厂 boot_a 完整备份**，sha256 `5364ec155d88cbd86a43d04aa9d147251ba4a204a9c78de7f83a48ed94b5250e`；版本串 `5.15.194-android13-8-00019-gf4321180a397-ab15212794`；回滚用 |

### 2.3 仓库内容

```
los/                     LineageOS 基线流水线（唯一构建流水线）
  config/                sources.lock.json（版本锁）、device-baseline.config（221KB 设备基线）、
                         droidspaces.config、extras.config、anykernel.sh
  patches/               7 个补丁（1 个 ABI padding + 1 个 BBG + 5 个优化）
  scripts/               prepare-runner / prepare / build / package / make_bootimg /
                         check_module_abi / elf_versions / verify_git_tree
  evidence/              vendor-module-versions.json（404 个原厂模块的 __versions 证据）
.github/workflows/build-los.yml   唯一 CI 工作流
tools/                   本地辅助工具（构建监控 / 产物校验 / 设备验收）
README.md                项目说明（用户向）
HANDOFF.md               本文档（维护向）
LICENSE                  MIT 许可全文（脚本/配置带 SPDX 标识；第三方源码与补丁按其原始许可）
```

---

## 3. 系统与内核规格

### 3.1 设备与系统

| 项目 | 值 |
|---|---|
| 机型 | Redmi K60 Pro，代号 `socrates`，SM8550 / kalama，22127RK46C |
| 系统 | HyperOS 3.0.304.0.WMKCNXM（Android 16，`BP2A.250605.031.A3`），原厂官方 ROM |
| 分区 | A/B 设备，当前槽 `_a`；内核位于 `boot` 分区（`boot_a` → `/dev/block/sde14`） |
| Bootloader | 已解锁（`fastboot boot/flash` 可用） |
| Root 方案 | KernelSU **LKM 模式**（ksud 3.3.1，`su` 上下文 `u:r:ksu:s0`；内核不内置 KSU） |
| 平台文件 | `vendor_dlkm` / `vendor_boot` / `init_boot` / `dtbo` 等均为原厂，未改动 |

### 3.2 内核与工具链（锁定于 `los/config/sources.lock.json`）

| 项目 | 值 |
|---|---|
| 源码 | LineageOS `android_kernel_xiaomi_sm8550`，分支 `lineage-23.2`，commit `093e3da978e7b954d041a261d40975957c7fe6f1` |
| archive sha256 | `62c4c1dbe72dec89b37ff9b903791ed3334f5977baa90681ab1d98f6d070215a` |
| Linux 版本 / 版本串 | 5.15.211 / `5.15.211-g093e3da978e7` |
| 工具链 | AOSP Clang r563880c（21.0.0）；prebuilts commit `9916fb51ccb914d62d35ad9a7b9b21d2ef046928`，tree `571ed3e20b5708cea1177d5072853fc5b85b6877` |
| LTO | ThinLTO（`CONFIG_LTO_CLANG_THIN=y`，`FULL` 关闭） |
| 安全/ABI 配置 | `MODVERSIONS=y`、`CFI_CLANG=y`、`KASAN_HW_TAGS=y`、`SHADOW_CALL_STACK=y`、`MODULE_SIG_PROTECT=y`、`TRIM_UNUSED_KSYMS` 关闭 |
| 构建机 | GitHub `ubuntu-24.04` runner（4 vCPU / 16GB / ~145GB 盘），CI 自动构建 |

### 3.3 功能相关配置（已在 `kernel-los.config` 中核对）

- **Droidspaces**：`SYSVIPC`、`POSIX_MQUEUE`、`IPC_NS`、`PID_NS`、`USER_NS`、`NET_NS`、`UTS_NS`、`DEVTMPFS`、
  `TMPFS`、`MACVLAN`、`IP_SET`、`IP6_NF_TARGET_MASQUERADE`、`NETFILTER_XT_MATCH_ADDRTYPE` 等全部 `=y`；
  `SYSVIPC` 通过 task_struct 槽 6/7/8 的 ABI padding 开启（不破坏 kABI）。
- **BBG**：`CONFIG_BBG=y`；`CONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,baseband_guard,smack,tomoyo,apparmor,bpf"`；
  `CONFIG_BBG_BLOCK_BOOT` / `CONFIG_BBG_BLOCK_RECOVERY` **未开启**（boot / recovery 在 BBG 白名单中）。
- **游戏优化**：`LRU_GEN_ENABLED=y`、`DEFAULT_FQ_CODEL=y`、`NET_SCH_FQ_CODEL=y`、`NET_SCH_FQ=y`、`NET_SCH_CAKE=y`、
  `TCP_CONG_BBR=y`；补丁 `0020`–`0024`（sched 扫描顺序、dcache 减压、`clear_page` 16B 对齐、`int_sqrt`、alarmtimer）。

### 3.4 版本串策略（重要）

- 本内核 `uname -r` 为 **`5.15.211-g093e3da978e7`**，与官方 `5.15.194-android13-8-...` 不同，**这是预期行为**：
  原厂模块带 `__versions`，内核比对 vermagic 时对带 CRC 的模块忽略 release 段；
  **真正决定驱动能否工作的是符号 CRC / 结构体布局（KMI），本内核 0 差异**。
- 不要尝试把版本串改回官方值"求稳"——那只是字符串，不改变 ABI；也不要启用 `TRIM_UNUSED_KSYMS`（会破坏 vendor 模块依赖）。

---

## 4. 关键技术决策与踩坑记录

### 4.1 官方内核无法用公开源码复现
官方固件内核 banner 从 `-00019-gf4321180a397` 看像是 ACK `5.15.194`，但实际是小米用自家 5.15.78 vendor 树
（clang r450784e）编译后**改了版本串伪装成 GKI**；MiCode 公开的 `socrates-t-oss` 只有 5.15.41。
因此拿 ACK 源码无论如何都复现不出官方 ABI。

### 4.2 ACK 路线（已废弃，勿重走）
曾用 ACK 5.15.194（`f4321180a397`）+ clang 21 构建 v3/v4：内核能开机、能加载 402 个模块（靠忽略 CRC 的补丁），
但 **扬声器、摄像头失效**——原因是 ACK 与官方 vendor 树的结构体布局/调用约定不兼容（不是 CRC 值的问题）。
v3/v4 相关 Release/分支已删除，仅保留经验：**不要用 CRC 忽略补丁掩盖 ABI 不兼容**。

### 4.3 改用 LineageOS 内核的依据
LineageOS `android_kernel_xiaomi_sm8550` 与官方内核同属高通 msm-kernel vendor 树血统（KMI gen8），
其导出符号 CRC 与结构体布局与官方 vendor 模块一致；同机型已有成功先例。实测结果见 §7：**0 CRC mismatch**。

### 4.4 ABI 验证方法
- 证据文件：`los/evidence/vendor-module-versions.json`
  - 结构：`{ "kernel_exports": [...], "modules": { "<模块名>.ko": { "<符号>": "0x<CRC>" } }, "vendor_exports": [...] }`
  - 来源：设备 `/vendor_dlkm/lib/modules/*.ko`（404 个）的 `__versions` 节；导出符号分类来自设备 kallsyms。
- 校验脚本：`los/scripts/check_module_abi.py <Module.symvers> <evidence.json> --report <out.json>`
  - 比对每个模块导入符号的 CRC 与本次构建 `Module.symvers` 导出的 CRC；
  - `crc_mismatches`：CRC 不一致（或设备导出但本次构建缺失）→ 驱动必坏；
  - `not_in_kernel_symvers`：符号由**其它厂商模块**导出（正常，运行时相互依赖）；
  - `unclassified_missing_imports`：既不在内核也不在厂商模块导出（应为空）。
- 本地解析单个 `.ko`：`los/scripts/elf_versions.py` 的 `module_versions(data)`。
- **注意**：`build.sh` 中 ABI 检查**非致命**（失败只记录 `abi=ABI_MISMATCH` 并继续打包/发布），
  因此接手后必须人工校验 `build-los.json` 的 `abi.unique_crc_mismatch == 0`。

### 4.5 ThinLTO 决策
- 最初按设备基线用 **Full LTO**（`LTO_CLANG_FULL=y`），run 3 卡在第 68 分钟失败：prepare 全部成功、
  build 日志丢失（`log not found`）→ GitHub runner 内存不足/失联（Full LTO 链接阶段）。
- 改为 **ThinLTO**：`los/scripts/build.sh` 在 `cp baseline out/.config` 之后对
  `kernel/arch/arm64/configs/gki_defconfig` 与 `out/.config` 执行
  `--enable LTO_CLANG_THIN` / `--disable LTO_CLANG_FULL`，自检断言相应改为 `THIN=y` 且 `FULL!=y`。
- 构建时间从 >68 分钟降至 **build 16m35s / 整轮 20m31s**；ThinLTO 与 Full LTO 生成代码等价，
  **不影响 genksyms CRC、CFI 类型哈希、vermagic**。
- workflow 里仍保留"分配 swap"步骤作为内存兜底（磁盘不足时跳过、不再硬失败）。

### 4.6 BBG 的默认行为（容易误解，务必看）
- Baseband-guard 把 **`u:r:su:s0` / `u:r:magisk:s0` / `u:r:ksu:s0` 域发起的进程标记为"非受信"**，
  其它系统进程视为受信；对非受信进程，拦截对**非白名单块设备**的写、`setattr`（chmod 等）和破坏性 ioctl
  （`BLKDISCARD` / `BLKZEROOUT` / `BLKRRPART` 等）。
- 白名单（放行）分区由 `security/baseband-guard/baseband_guard.h` 中 `allowlist_names` 决定：
  默认包含 `boot`、`init_boot`、`vendor_boot`、`vendor_kernel_boot`、`dtbo`、`userdata`、`cache`、`metadata`、
  `misc`、`vbmeta*`、`recovery`（受 `CONFIG_BBG_BLOCK_BOOT` / `CONFIG_BBG_BLOCK_RECOVERY` 影响）。
- **本内核默认不保护 boot / recovery**（两项 Kconfig 未开），保护的是 modem / persist 等关键分区；
  实测：root 下 `chmod` `persist` / `modem_a` 被拒（EPERM + dmesg 日志），`boot_a` 放行。
- 因此"防格机"对格机脚本（通常以 root/KSU 身份运行、写 modem/persist 等）生效；对 fastboot 线刷无效（那是 bootloader 层）。

### 4.7 KernelSU LKM 兼容
- 内核**没有内置 KernelSU**；设备原有 KernelSU LKM 模式（`kernelsu.ko` 由 KernelSU 管理器加载到内核）。
- 因为本内核与原厂模块 ABI 一致，KernelSU 的 LKM 模块可正常加载，root / 模块功能不受影响（实测 `uid=0 context=u:r:ksu:s0`）。

### 4.8 已知"非问题"（避免接手者误判）
| 现象 | 说明 |
|---|---|
| CPU governor 为 `powersave`，各簇频率被固定在某个值 | HyperOS 的 perf 栈（PerfShrike / mi_thermald）通过 `scaling_min/max_freq` 控制频率，`powersave` 是 MIUI 常态设置，不是内核缺陷 |
| dmesg 有少量 `avc: denied`（如 `/dev/metis`、`vendor_default_prop`） | MIUI 系统组件自身的 sepolicy 行为，与内核无关；原厂内核同样存在 |
| `abi-report` 中 `not_in_kernel_symvers` 有 573 个符号 | 由其它厂商模块导出，属正常 |
| `evidence` 404 个 `.ko` 有 4 个没加载（`llcc_perfmon`、`mmrm_test_module`、`qca_cld3_kiwi`、`qca_cld3_qca6490`） | debug/test 模块与其它平台/机型 WiFi 模块，原厂系统也不加载；`kiwi_v2` 即 `qca_cld3_kiwi_v2.ko` 的模块名 |
| 构建日志 `extras not enabled: CONFIG_TCP_ECN` | 5.15 内核没有该 CONFIG，属预期告警 |
| `WLAN MAC address is not set` / `adsp_sleepmon ... failed -12` 等早期启动日志 | 原厂系统同样会出现，非本次内核引入 |

### 4.9 CI / 环境基建坑（已修复，接手时注意）
| 坑 | 现象 | 修复方式 |
|---|---|---|
| clang 大包下载截断 | `gzip: unexpected end of file` / `tar: Unexpected EOF` | `prepare.sh` 中用 `curl` + `gzip -t` + 重试校验 |
| 补丁打不上 | `0001-sysvipc` 失败 | 统一 `patch --batch --fuzz=N --strip=1`，各补丁单独 fuzz 策略 |
| kernel tarball 完整性 | 下载被代理/网络截断 | 校验 sha256 + Gitiles tree JSON（`verify_git_tree.py`） |
| Full LTO OOM | 构建 68 分钟后 runner 失联 | 改 ThinLTO（§4.5） |
| GitHub API 限额 | `gh`/API 403/耗尽 | 用 Actions 页面 HTML 解析（`tools/parse_actions.py`、`tools/monitor_run.ps1`） |
| 本地 push 失败 | DNS/代理不稳定 | 直连 SSH：`git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push origin main` |
| 临时调试 workflow | 曾用 `.debug/` + `debug-run.yml` 抓日志 | 已全部删除，不再可用；需要日志看 Actions job 页面 |
| Release 资产 | 同名 tag 重跑需覆盖 | workflow 用 `gh release upload --clobber` |
| 修改 `los/**` 曾触发重建 | 2026-11-26 仅改注释/加 SPDX 头（提交 `6188e65`）也会自动重建，Release 资产被覆盖且二进制哈希变化 | **2026-11-27 起已关闭 push 自动构建**：workflow 只保留 `workflow_dispatch`，重建必须手动 Run workflow |
| Release 说明正文 | 首次创建后不再更新（重建只换资产） | 许可/变更说明放仓库文档与包内 LICENSE；有 token 时可 `gh release edit` |

---

## 5. 仓库与构建流水线

### 5.1 CI 工作流 `.github/workflows/build-los.yml`

- **触发**：**仅手动** `workflow_dispatch`（Actions 页面 → Run workflow）；
  2026-11-27 起已移除 push 自动触发（原规则为 push 修改 `los/**` 或该 workflow 文件）
- **并发**：`group: build-los`，`cancel-in-progress: true`（新 run 会取消旧 run）
- **权限**：`contents: write`（用于创建 Release / 上传资产）
- **超时**：150 分钟；runner：`ubuntu-24.04`
- **步骤与耗时（run 4 `45797343370` 实测）**：

| 步骤 | 说明 | 耗时 |
|---|---|---|
| Prepare runner | 释放磁盘 + 安装构建依赖 | 2m26s |
| Restore compiler cache | 缓存 clang r563880c（命中） | 24s |
| Fetch sources, compiler, patches | 下载内核 tarball / 工具链，应用 7 个补丁 | 43s |
| Save compiler cache | 缓存未命中时才保存（本次跳过） | — |
| Allocate link memory | 分配 swap 兜底（磁盘不足自动跳过） | <1s |
| Build kernel | ThinLTO：`make Image modules`（timeout 6600s） | **16m35s** |
| Package boot.img / AnyKernel3 | `make_bootimg.py` + AnyKernel3 zip + sha256 + release notes | 5s |
| Publish release | 创建/更新 `k60p-kernel-los-v1` 并上传 7 个资产 | 6s |
| Collect / Upload artifacts | 步骤结果 + `los/dist/` 全量 artifact（保留 30 天，名 `los-kernel-<run_number>`） | 4s |

### 5.2 构建脚本职责

| 脚本 | 职责 |
|---|---|
| `los/scripts/prepare-runner.sh` | 清理磁盘、安装依赖、准备构建环境 |
| `los/scripts/prepare.sh` | 读 lock 文件；下载内核 tarball/clang（sha256 + gzip 完整性 + 重试）；应用 `los/patches/`；写 `.scmversion`；生成 `dist/source.patch` |
| `los/scripts/build.sh` | 基线 config → 注入 Droidspaces / extras / BBG LSM / ThinLTO → `olddefconfig` → **配置自检**（断言关键 CONFIG）→ `make Image modules`（timeout）→ UTS_RELEASE 断言 → **ABI 对比** → 写 `build-los.json` / `status-los.txt` |
| `los/scripts/package.sh` | 生成 `boot-los.img`（header v4）、AnyKernel3 zip、`SHA256SUMS-los`、`RELEASE-los.md` |
| `los/scripts/check_module_abi.py` | Module.symvers vs 设备模块证据的 CRC 对比 |
| `los/scripts/make_bootimg.py` | Android boot header v4 打包（page 4096、无 ramdisk） |
| `los/scripts/elf_versions.py` | 解析单个 `.ko` 的 `__versions` |
| `los/scripts/verify_git_tree.py` | 用 Gitiles tree JSON 校验源码 tarball |

### 5.3 补丁清单（`los/patches/`，均为第三方上游补丁，作者见文件头）

| 补丁 | 内容 | 来源 |
|---|---|---|
| `0001-sysvipc-kabi-padding-6-7-8.patch` | SYSVIPC task_struct ABI padding（槽 6/7/8） | nullptr-t-oss / Droidspaces |
| `0010-baseband-guard-5.15.patch` | Baseband-guard LSM（防格机） | vc-teahouse/Baseband-guard @ `48d9fde` |
| `0020-sched-adjust-cpu-scan-order.patch` | EAS 空闲 CPU 扫描顺序优化 | Hao Jia (ByteDance) |
| `0021-arm64-clear-page-16bytes-align.patch` | `clear_page` 16 字节对齐 | Sultan Alsawaf |
| `0022-lib-int-sqrt.patch` | 更快整数平方根 | FlyFrog |
| `0023-alarmtimer-minimise-wakeup-time.patch` | alarmtimer 唤醒最小化 | xNombre |
| `0024-dcache-reduce-cache-pressure.patch` | dentry/inode 缓存减压 | Tyler Nijmeh |

> **AnyKernel3 许可**：AK3 模板脚本采用 **BSD-3-Clause 风格的自定义许可**（Copyright © 2019 Chris Renshaw / osm0sis，
> 要求保留版权声明与免责声明、不得用作者名义背书），并非 GPL；其随包二进制许可各异
> （`magiskboot`/`magiskpolicy` GPL-3.0+、`busybox` GPL-2.0、lptools/fec/snapshotupdater Apache-2.0、httools MIT 等，
> 详见 AK3 仓库 `LICENSE` 文件及其中的源码链接）。本仓库 `ak3-los.zip` 打包时保留 AK3 `LICENSE`，
> 并额外放入本仓库 MIT 许可 `LICENSE.k60p-kernel.txt`（见 `los/scripts/package.sh`）。

---

## 6. 运维手册

> 设备连接：`R:\platform-tools\adb.exe` / `fastboot.exe`（Windows）。adb offline 时：
> `adb kill-server && adb start-server && adb reconnect offline`。

### 6.1 重新构建（**手动触发**，push 不会自动构建）
1. 打开 Actions：https://github.com/zhihan233/k60p_Kernel/actions/workflows/build-los.yml
2. 右上角 **Run workflow** → 选 `main` 分支 → Run
3. 预计 18–20 分钟；成功后自动发布到 Release `k60p-kernel-los-v1`（同名资产覆盖，二进制哈希会变化）

> 2026-11-27 起已移除 push 自动触发：改 `los/**`（包括只加注释）**不会**再自动构建；
> 纯文档/工具改动（README、HANDOFF、tools/）也完全不会触发。

### 6.2 监控构建（无需 GitHub API token）
```powershell
# 1) 方法 A：解析 Actions 列表页
Invoke-WebRequest "https://github.com/zhihan233/k60p_Kernel/actions?x=$(Get-Random)" -OutFile work/actions.html
python tools/parse_actions.py work/actions.html

# 2) 方法 B：轮询 job 页面 HTML 的步骤状态（推荐，可看到每步状态与耗时）
#    先取 run id 与 job id，然后：
powershell -File tools/monitor_run.ps1 -RunId <run_id> -JobId <job_id>
```
> 历史经验：runner 在 Full LTO 阶段可能失联导致日志不可用；ThinLTO 下未再出现。

### 6.3 下载与校验 Release
```powershell
powershell -File tools/fetch_release.ps1           # 下载到 deliver/
# 或手动：https://github.com/zhihan233/k60p_Kernel/releases/download/k60p-kernel-los-v1/<file>
```
```bash
sha256sum -c SHA256SUMS-los
python tools/check_boot.py deliver/boot-los.img    # 校验 header v4 / kernel_size / 版本串
python tools/check_readme.py                       # README 结构自检（可选）
```

### 6.4 刷入 / 回滚（用户已永久刷入，如需重刷）
```bash
# 刷入（先备份原厂 boot；A/B 设备当前槽为 _a）
adb shell "su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/Download/stock-boot.img bs=1M'"
adb pull /sdcard/Download/stock-boot.img
adb reboot bootloader
fastboot boot boot-los.img        # 先临时验证
fastboot flash boot boot-los.img  # 确认后永久刷入
fastboot reboot

# 回滚
fastboot flash boot stock-boot_a.img   # deliver/ 中的原厂备份
```
> 也可以刷 `ak3-los.zip`（AnyKernel3，`BLOCK=boot`、支持 A/B）。
> **OTA 前**务必先回滚原厂 boot，否则 OTA 校验可能失败。

### 6.5 设备端验收
```bash
adb push tools/device_test.sh /data/local/tmp/device_test.sh
adb shell "su -c 'sh /data/local/tmp/device_test.sh'"     # 输出在 /data/local/tmp/kern-test/
adb pull /data/local/tmp/kern-test work/device-test
```
判读标准（本次实测值）：

| 检查项 | 期望 |
|---|---|
| `uname -r` | `5.15.211-g093e3da978e7` |
| `/proc/modules` 行数 | 401（400 原厂 + `kernelsu`），0 加载失败 |
| dmesg `disagrees about version` / `CFI failure` / `Unknown symbol` | 0 行 |
| dmesg `WARNING/BUG/Oops/Call trace/panic` | 0 行 |
| `/sys/kernel/security/lsm`（root，先挂 securityfs） | 含 `baseband_guard` |
| `cat /sys/kernel/mm/lru_gen/enabled` | `0x0003` |
| `tc qdisc show dev wlan0` | 含 `fq_codel` |
| `net.ipv4.tcp_available_congestion_control` | 含 `bbr` |

补充脚本：`device_test2.sh`（BBG/Droidspaces/电源/网络）、`device_test3.sh`（屏幕/governor/GPU/qdisc）、
`device_test4.sh`（Droidspaces/蓝牙/显示/命名空间）、`device_test5.sh`（BBG 功能实测）、`device_test6.sh`（白名单/蜂窝/异常统计）。

### 6.6 故障排查

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 开机卡 logo / 黑屏 | boot 镜像错误或与 ROM 不匹配 | 长按电源 10s 重启回原厂；`fastboot boot` 先验证；必要时 `fastboot flash boot stock-boot_a.img` |
| 扬声器 / 摄像头异常 | vendor 模块与内核 ABI 不符（换了 ROM / 版本） | 核对 `dmesg` 的 `disagrees about version`；确认系统为 HyperOS 3.0.304.0.WMKCNXM；必要时按新 ROM 重建证据与内核 |
| 模块加载失败 | 同上，或 `TRIM_UNUSED_KSYMS` 被误开 | 检查 `kernel-los.config`；重跑 ABI 报告 |
| 构建 ABI 报告非 0 | 源码/配置/工具链被改动 | 比对 `los/config/sources.lock.json` 与 `los/patches/`；**不要用 CRC 忽略补丁掩盖** |
| CI 构建失败 | 下载截断 / runner OOM / 编译错误 | 看 job 页面步骤状态与日志；确认 ThinLTO 仍在；必要时降低 `JOBS` |
| Release 上传失败 | token 权限 / 资产名冲突 | `gh release upload --clobber` 已处理；重跑 workflow |
| adb offline | USB 连接状态 | `adb kill-server; adb start-server; adb reconnect offline`；重新插拔 |
| push 失败 | DNS/网络/代理 | 重试；直连：`git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push origin main` |

### 6.7 网络与代理（仅本地需要，CI runner 自带外网）
- 本地访问 GitHub 网页 / Release 资产、`android.googlesource.com`、`raw.githubusercontent.com`、gnu.org 等
  可能需代理：`http://127.0.0.1:7897`（curl 用 `-x`）。
- Git push 走 SSH 443 直连（`ssh.github.com`，通常解析为 `20.205.243.160`）；偶发 DNS 失败重试即可。
- 仓库没有落盘任何 GitHub token；CI 内自动使用 `${{ github.token }}` 发布 Release。
  本地无法调用 GitHub API 删除 Release 对象（如需操作请用网页或提供 token）。

---

## 7. 实测记录（2026-11-26）

### 7.1 环境与时间线
- **18:01** 切 ThinLTO 提交（`8a94029`）→ run 4 `45797343370` 成功（20m31s）
- **18:22** 自动发布 Release `k60p-kernel-los-v1`
- **18:30** 下载并校验产物（sha256 全部匹配；ABI `crc_mismatches=0`）
- **19:09** 用户告知已在 `fastboot boot` 临时启动下完成人参与的测试（扬声器/麦克风/摄像头）并通过；
  agent 随后跑完终端测试（下节）
- **20:08** 因 SPDX 许可提交 `6188e65` 修改了 `los/scripts/`，**意外触发 run 5** `45816824406`
  （17m22s 成功），Release 资产被重建覆盖（哈希变化，当时未同步文档）
- **20:52** 复核 `boot_a` 前 43,315,200 字节 sha256 = run 4 的 `bf6db3cc…` → **确认已永久刷入**
  ——设备当前运行的是 **run 4 构建的镜像**
- **2026-11-27 08:37–08:56** 许可证改为 MIT 的提交 `12c2b6c` 触发 **run 6** `45917853438`
  （约 18 分钟成功，build 14m），Release 重建；ABI 仍 0 mismatch；`ak3-los.zip` 内含
  AK3 `LICENSE` 与本仓库 MIT `LICENSE.k60p-kernel.txt`
- 设备当前运行：`Linux version 5.15.211-g093e3da978e7 (socrates@github-actions) ... clang version 21.0.0`
  （run 4 镜像；Release 现为 run 6 构建，源码与 ABI 相同、二进制哈希不同）

### 7.2 逐项结果（原始数据摘录）

| 项目 | 结果 |
|---|---|
| 开机 | ✅ 正常进入系统（`mWakefulness=Awake`，`DisplayDeviceInfo state ON`） |
| 扬声器 / 麦克风 / 录音 | ✅ 用户实测正常；`/proc/asound/cards` 有 `kalama-mtp-snd-card`，audio HAL 运行 |
| 摄像头（前后/录像） | ✅ 用户实测正常；`/dev/video0/1/32/33`，cameraserver + vendor provider 运行 |
| WiFi | ✅ `wlan0` 11ax，Link speed 2401Mbps，RSSI -18dBm，ping 外网 0% 丢包 |
| 蜂窝 / 基带 | ✅ 中国移动 NR_SA（`mServiceState=IN_SERVICE`，`ssRsrp=-83`） |
| 充电 / 电池 | ✅ `status=Charging`、`current_now=379000`、`constant_charge_current=5000000`、温度 24.4°C |
| 显示 / 触摸 | ✅ 1440×3200，支持 60 / 90 / 120Hz 模式 |
| 蓝牙 | ✅ HAL（`android.hardware.bluetooth@1.1-service-qti`）+ `com.android.bluetooth` 运行 |
| KernelSU LKM | ✅ `su -c id` → `uid=0(root) ... context=u:r:ksu:s0`；ksud 3.3.1；`kernelsu` 模块已加载 |
| 内核模块 | ✅ `/proc/modules` 401；dmesg 无 `disagrees about version` / `CFI failure` / `Unknown symbol` / `invalid module format` |
| **BBG 防格机** | ✅ LSM 运行时列表：`capability,safesetid,selinux,baseband_guard`；root `chmod` `persist`/`modem_a` → `Operation not permitted`，dmesg：`baseband_guard: deny setattr on protected partition dev=... pid=... comm=chmod`；白名单 `boot_a` 放行 |
| Droidspaces | ✅ App 运行；`unshare -Ur`、`unshare -Urmpf` 均 rc=0；cgroup v2 / `/sys/fs/cgroup/droidspaces` 正常 |
| 内核稳定性 | ✅ dmesg 中 `WARNING/BUG/Oops/Call trace/panic` 计数全 0 |
| 内核特性 | ✅ `lru_gen/enabled=0x0003`；默认 qdisc `fq_codel`；`tcp_available_congestion_control=reno bbr cubic`；zram0 12GiB（`lzo-rle`） |

### 7.3 构建期 ABI 报告（`abi-report-los.json` 摘录，数组已省略）

```text
modules:                        401
matched_symbols:                3971
crc_mismatches:                 []（0 个）
not_in_kernel_symvers:          573 个（由其它厂商模块导出，正常）
unclassified_missing_imports:   []（0 个）
scope: "Imported symbol CRCs; external exports classified using device kallsyms."
```

`build-los.json` 摘要（run 6 `45917853438`）：`kernel_release=5.15.211-g093e3da978e7`、
`ci_commit=12c2b6c48bfd…`、`abi.unique_crc_mismatch=0`、`abi.missing_symbols=0`
（run 4 `45797343370` / commit `8a94029` 的 ABI 数值完全一致）。

---

## 8. 已知限制与风险

1. **仅验证 HyperOS 3.0.304.0.WMKCNXM（Android 16）**：换 ROM / 版本（vendor 分区变化）后 vendor 模块 ABI 可能不同，
   需重新生成证据并重测（见 §4.4）。
2. **boot.img 无原厂 AVB 签名**：必须保持 Bootloader 解锁；回锁无法启动。系统 OTA 前应回滚原厂 boot。
3. **BBG 默认不保护 boot / recovery**（Kconfig 未开），只保护 modem / persist 等分区；如需保护可在
   `los/config/device-baseline.config` 中打开 `CONFIG_BBG_BLOCK_BOOT` / `CONFIG_BBG_BLOCK_RECOVERY` 重新构建。
4. **未内置 KernelSU**：依赖设备原有 LKM 模式；若用户改用其他 root 方案需自行评估。
5. **仅验证了 ThinLTO 产物**；Full LTO 在 CI 上会 OOM，不作为可复现路径。
6. **游戏优化为常规项**（BBR v1、fq_codel、MGLRU、sched/内存小补丁），未做 BBRv3 / 游戏调度专项调参。
7. **未做长时间稳定性/待机测试**：未验证深层 suspend 长时间待机、长时间游戏/快充热稳定性。
8. **ABI 检查非致命**：构建不会因 ABI 不一致而红，必须人工看 `build-los.json`（见 §4.4）。
9. **证据文件是静态快照**：`los/evidence/vendor-module-versions.json` 不会自动更新，升级 ROM 后必须重建。
10. **构建非字节可复现**：同一份源码不同次 CI 构建的 Image / boot 哈希不同（run 4 / 5 / 6 实测各不相同，
    见 §2.1）；不影响 ABI 与功能，但**不要跨构建比对哈希**，以 Release 内 `SHA256SUMS-los` 为准。
11. **Release 说明正文不随重建更新**：正文为首次创建时生成（run 4），后续重建只覆盖资产；
    许可文本以 `ak3-los.zip` 内 `LICENSE` / `LICENSE.k60p-kernel.txt` 为准。

---

## 9. 待办与可选增强

**必做**：无（交付已完成，设备已永久刷入）。

可选（按优先级）：
1. **ROM 升级跟进**：升级前记录当前 `boot_a` 状态；升级后重跑 ABI 报告与 §6.5 验收。
2. **BBRv3 backport**（若需要更强游戏网络性能；注意 kABI 安全）。
3. **BBG 保护范围决策**：是否开启 `CONFIG_BBG_BLOCK_BOOT` / `RECOVERY`（会禁止 root 工具写 boot/recovery）。
4. **长期稳定性测试**：待机 / suspend、长时间游戏、快充热稳定性。
5. **ABI 检查改为致命**（若希望 CI 在 ABI 不一致时直接失败）。
6. **证据收集脚本入库**（当前 evidence 由一次性脚本生成，格式见 §4.4）。
7. 有 token 时可更新 Release 说明正文 / 清理历史 Release 对象。

---

## 10. 交接检查清单（接收方逐项确认）

- [ ] 能访问 GitHub 仓库 https://github.com/zhihan233/k60p_Kernel（main 分支）
- [ ] 本地工作区 `D:\Administrator\Documents\ai\k60p_build` 存在，`deliver/` 中是 run 4 产物（设备当前镜像，sha256 见 §2.2）
- [ ] 阅读 `README.md`（用户向说明）与本文档
- [ ] 确认设备当前状态：已永久刷入（`adb shell uname -r` = `5.15.211-g093e3da978e7`；
      `boot_a` 前 43,315,200 字节 sha256 = `bf6db3cc…`，即 run 4 boot 镜像；Release 现为 run 6 重建版）
- [ ] 保留 `deliver/stock-boot_a.img`（原厂 boot 备份，回滚用）
- [ ] 能触发并监控一次构建（§6.1 / §6.2）
- [ ] 能用 `tools/device_test.sh` 复跑设备验收（§6.5）
- [ ] 了解本地无 GitHub token（Release 正文修改需网页/新 token）
- [ ] 了解网络环境（代理端口、SSH 443 直连 push 方式）
- [ ] 了解"版本串不同属预期"与"boot 未签名需解锁"

---

## 11. 时间线与变更记录

| 日期/时间 | 事件 |
|---|---|
| 2026-11-26 14:00 | ACK 路线 Full LTO 构建 run 3 `45755782891` 失败（68 分钟 runner 失联） |
| 2026-11-26 18:01 | 切换 ThinLTO 提交 `8a94029`，run 4 `45797343370` 成功（20m31s，build 16m35s） |
| 2026-11-26 18:22 | 自动发布 Release `k60p-kernel-los-v1` |
| 2026-11-26 18:30 | 下载校验产物：ABI `crc_mismatches=0`，boot 镜像 header/版本串/sha256 全部通过 |
| 2026-11-26 19:10–19:15 | 用户临时启动实测（人参与项通过）+ agent 终端验收全通过 |
| 2026-11-26 19:25 | 清理旧 ACK 流水线、调试设施、旧分支/tag；仓库只保留 LOS 流水线 |
| 2026-11-26 19:35–20:30 | README 重构与全面审校；新增 GPL-2.0 LICENSE 与 SPDX 标识 |
| 2026-11-26 20:52 | 复核确认 `boot_a` 已写入 run 4 构建的内核（永久刷入生效，boot sha256 `bf6db3cc…`） |
| 2026-11-26 20:55 | 生成本正式交接文档（v1.0） |
| 2026-11-26 20:08→20:25 | SPDX 许可提交 `6188e65` 意外触发 **run 5** `45816824406`（17m22s 成功），Release 资产被重建覆盖（哈希变化） |
| 2026-11-27 08:40 | 许可证调整：自写代码 GPL-2.0-only → **MIT**（LICENSE/SPDX/README/HANDOFF）；`package.sh` 在 ak3 zip 内附带 MIT 许可文本 |
| 2026-11-27 08:37→08:56 | 触发 **run 6** `45917853438`（约 18 分钟，build 14m）：ABI 仍 0 mismatch；`ak3-los.zip` 含 AK3 `LICENSE` + `LICENSE.k60p-kernel.txt` |
| 2026-11-27 09:00 | 更新 README / 交接文档中的 Release 哈希与"非字节可复现"说明（v1.2） |
| 2026-11-27 09:20 | **关闭 push 自动构建**：`build-los` 仅保留 `workflow_dispatch`，重建改为手动；文档同步更新（v1.3） |

---

## 附录 A：常用命令速查

```bash
# 构建（手动）
#   Actions 页面 → build-los → Run workflow
# 设备
adb devices && adb shell su -c 'uname -r'
adb reboot bootloader && fastboot devices
fastboot boot boot-los.img                               # 临时启动
fastboot flash boot boot-los.img                         # 永久刷入
fastboot flash boot stock-boot_a.img                     # 回滚原厂
# 设备验收
adb push tools/device_test.sh /data/local/tmp/ && adb shell "su -c 'sh /data/local/tmp/device_test.sh'"
# 本地校验
sha256sum -c SHA256SUMS-los
python tools/check_boot.py deliver/boot-los.img
# 仓库
git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push origin main
```

## 附录 B：关键文件索引

| 路径 | 作用 |
|---|---|
| `los/config/sources.lock.json` | 内核/工具链/补丁版本的唯一锁文件（改版本只改这里） |
| `los/config/device-baseline.config` | 从设备抓取的 LOS 基线配置（221KB） |
| `los/config/droidspaces.config` / `extras.config` | 功能开关（容器 / 游戏） |
| `los/config/anykernel.sh` | AnyKernel3 配置（`BLOCK=boot`、A/B、`supported.versions=16`） |
| `los/scripts/build.sh` | 构建主脚本（含 ThinLTO 切换、配置自检、ABI 检查） |
| `los/evidence/vendor-module-versions.json` | ABI 证据（404 个模块的导入 CRC） |
| `tools/device_test*.sh` | 设备端验收脚本（root 执行） |
| `tools/monitor_run.ps1` / `parse_actions.py` | 无 API 的构建监控 |
| `tools/check_boot.py` / `fetch_release.ps1` | boot 镜像校验 / Release 下载 |
| `deliver/stock-boot_a.img` | 原厂 boot 备份（回滚用，gitignore） |

## 附录 C：许可与第三方来源

- 本仓库自写脚本 / 配置：**MIT**（见 `LICENSE`；脚本文件头带 `SPDX-License-Identifier: MIT`）；
- 内核源码：LineageOS（GPL-2.0），`los/patches/` 中的补丁归各自上游作者（详见各补丁头与 README「模块来源」）；
- 第三方组件：Droidspaces（SYSVIPC padding）、vc-teahouse/Baseband-guard、osm0sis/AnyKernel3；
  AnyKernel3 脚本为 BSD-3-Clause 风格许可、随包二进制为 GPL-2.0 / GPL-3.0+ / Apache-2.0 / MIT 等（见 AK3 `LICENSE`）；
- 发布物 `ak3-los.zip` 同时包含 AK3 `LICENSE` 与本仓库 `LICENSE.k60p-kernel.txt`。

---

*本文档由 deepseek v4.1flash 于 2026-11-26 生成，随项目交付。*
