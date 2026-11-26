# Redmi K60 Pro (socrates) 5.15 定制内核 — LineageOS 基线

> ✅ 已在真机 `fastboot boot` 验证通过（2026-11-26）｜构建方式：GitHub Actions 云端编译

> [!WARNING]
> **⚠️ 刷机有风险，操作需谨慎！**
>
> - 刷入第三方内核**可能导致设备变砖、数据丢失、保修失效、无法开机**。
> - 刷入前请**备份数据与原厂 boot 分区**，确认 Bootloader 已解锁、自己有能力通过 fastboot / 9008 救砖。
> - **强烈建议先 `fastboot boot boot-los.img` 临时启动验证**，确认正常后再 `fastboot flash boot` 永久刷入。
> - 本内核已在实机验证（见下文），但**作者不对任何直接或间接损失负责**；刷机即代表你自行承担全部风险。
> - 请勿在未解锁（有锁）的设备上刷入；不同 ROM 版本之间可能存在兼容性差异。

---

## 项目简介

| 项目 | 内容 |
|---|---|
| 设备 | Redmi K60 Pro（`socrates`，SM8550 / kalama，22127RK46C） |
| 目标系统 | HyperOS 3.0.304.0.WMKCNXM（Android 16，原厂 vendor / 400+ 原厂内核模块） |
| 内核基线 | [LineageOS `android_kernel_xiaomi_sm8550`](https://github.com/LineageOS/android_kernel_xiaomi_sm8550)，`lineage-23.2` @ `093e3da978e7`（Linux **5.15.211**） |
| 版本串 | `5.15.211-g093e3da978e7` |
| 编译 | AOSP Clang r563880c（21.0.0），**ThinLTO** + CFI + MODVERSIONS + KASAN_HW_TAGS |
| 构建方式 | GitHub Actions（push 修改 `los/**` 自动触发，约 20 分钟） |

**为什么用 LineageOS 内核**：官方 HyperOS 内核是小米用自家 5.15.78 vendor 树编译并伪装成 GKI 版本串的，公开源码（MiCode `socrates-t-oss`）只有 5.15.41，无法复现其 ABI；而 LineageOS sm8550 内核与官方同属高通 msm-kernel vendor 树血统，kABI / 结构体布局一致。实测 **400 个原厂 vendor 模块全部加载（另有 KernelSU 的 `kernelsu`，合计 401 个模块），符号 CRC 0 差异**——这正是不换内核源码时厂商驱动（扬声器、摄像头等）能正常工作的关键。

---

## 功能特性

- **Droidspaces 容器支持**：GKI 5.15 官方配置 + **SYSVIPC kABI padding（task_struct 槽 6/7/8）** 补丁（Droidspaces 官方提供，内核配置要求见[官方文档](https://github.com/ravindu644/Droidspaces-OSS/blob/main/Documentation/Kernel-Configuration.md)）；
  `SYSVIPC` / `POSIX_MQUEUE` / `IPC_NS` / `PID_NS` / `USER_NS` / `NET_NS` / `UTS_NS` / `DEVTMPFS` / `TMPFS` / `MACVLAN` / `ipset` / IPv6 NAT / `NETFILTER_XT_MATCH_ADDRTYPE` 等全部开启。
- **BBG（Baseband-guard）防格机**：LSM 安全模块，拦截 `su` / `magisk` / `ksu` 等**非受信 root 进程**对 modem / persist 等关键分区的写入、`setattr` 与破坏性 ioctl（`CONFIG_BBG=y`；boot / recovery 分区是否保护可通过 Kconfig 选项 `CONFIG_BBG_BLOCK_BOOT` / `CONFIG_BBG_BLOCK_RECOVERY` 开启，本内核默认不保护 boot，避免影响正常刷内核）。
- **游戏 / 性能优化**：**MGLRU 默认开启**；默认队列 **fq_codel**（CAKE / FQ / FQ_CODEL 全量编译）；**BBR** 拥塞控制；CPU 扫描顺序优化、dcache 减压、`clear_page` 16 字节对齐、`int_sqrt`、alarmtimer 唤醒最小化等小补丁（补丁清单见 `los/patches/`）。
- **内核不内置 KernelSU**：沿用设备现有 **KernelSU LKM 模式**（`kernelsu` 模块由 KernelSU 管理器加载），实测 root 正常（`uid=0 context=u:r:ksu:s0`，ksud 3.3.1）。

---

## 实机验证结果（2026-11-26，`fastboot boot` 临时启动，HyperOS 3.0.304 原厂系统）

| 项目 | 结果 |
|---|---|
| 开机 / 系统启动 | ✅ 正常进入系统，无黑屏 / 异常重启 |
| 扬声器 / 麦克风 / 录音 | ✅ 实测正常 |
| 摄像头（前后 / 录像） | ✅ 实测正常 |
| WiFi / 网络 | ✅ `wlan0` 11ax 2401Mbps，ping 外网 0% 丢包 |
| 蜂窝网络 / 基带 | ✅ 中国移动 NR_SA（IN_SERVICE），信号正常 |
| 充电 / 电池 | ✅ USB 充电、5A 限流、温度 ~24°C |
| 显示 / 触摸 | ✅ 1440×3200，60 / 90 / **120Hz** 模式正常 |
| 蓝牙 | ✅ 协议栈服务运行（HAL + `com.android.bluetooth`） |
| KernelSU（LKM） | ✅ `su -c id` → `uid=0 ... context=u:r:ksu:s0` |
| 内核模块加载 | ✅ 401 个（400 原厂 + KernelSU）、**0 加载失败**；无 CRC / vermagic / CFI 报错 |
| **BBG 防格机** | ✅ LSM 含 `baseband_guard`；实测 root 对受保护分区（`persist` / `modem_a`）`chmod` → `Operation not permitted` + dmesg `baseband_guard: deny setattr on protected partition`；白名单（`boot_a`）正常放行 |
| Droidspaces | ✅ `unshare -Ur` / `unshare -Urmpf` 全部成功，cgroup v2 可用 |
| 内核稳定性 | ✅ dmesg 中 `WARNING / BUG / Oops / Call trace / panic` 计数均为 0 |
| 内核特性 | ✅ MGLRU=`0x0003`、默认队列 `fq_codel`、`bbr` 可用、zram 12GB（lzo-rle） |

> 说明：模块 ABI 报告（`abi-report-los.json`）显示 `crc_mismatches = 0`、`missing_symbols = 0`；
> 其中 `not_in_kernel_symvers` 的 573 个符号是由**其他厂商模块**导出的（属正常情况）；
> `los/evidence/vendor-module-versions.json` 收录的 404 个 `.ko` 中另有 4 个是 debug / 其它机型 WiFi 模块，原厂系统同样不会加载。

---

## 下载与刷入

**Release**：https://github.com/zhihan233/k60p_Kernel/releases/tag/k60p-kernel-los-v1

| 文件 | 说明 |
|---|---|
| `boot-los.img` | fastboot 用 boot 镜像（boot header v4，kernel 偏移 4096，无 ramdisk） |
| `ak3-los.zip` | AnyKernel3 刷机包（可配合 KernelSU / 刷机 App 使用） |
| `Image-los` | 裸内核 Image（自行打包用） |
| `SHA256SUMS-los` | 校验值 |
| `abi-report-los.json` / `build-los.json` | ABI 报告 / 构建元数据 |
| `kernel-los.config` | 最终内核配置（可自行核对所有 CONFIG） |

本次构建校验值：

```text
boot-los.img  bf6db3cc104de7293ca0fa846998ddcd9e8f2fd07ff7e75d7dce679348df953f  43,315,200 B
ak3-los.zip   b1819b07cf26c4ba26db5f607620f5e12f4504a57201e1c40180d104d6129eb6  22,597,425 B
```

校验方式：把 `SHA256SUMS-los` 与要刷的文件放在同一目录，执行 `sha256sum -c SHA256SUMS-los`。

### 刷入步骤（A/B 设备，只刷当前槽的 boot 分区）

> 前置条件：Bootloader 已解锁、电脑已安装 platform-tools、手机已开启 USB 调试（`adb devices` 能看到设备）。

```bash
# 0) 备份原厂 boot（设备已 root；当前槽位可用 getprop ro.boot.slot_suffix 查看，示例为 _a）
adb shell "su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/Download/stock-boot.img bs=1M'"
adb pull /sdcard/Download/stock-boot.img

# 1) 进入 fastboot
adb reboot bootloader

# 2) 先临时启动验证（不写分区，重启即回原系统）
fastboot boot boot-los.img

# 3) 确认一切正常后再永久刷入
fastboot flash boot boot-los.img
fastboot reboot
```

**回滚**：`fastboot flash boot stock-boot.img`（第 0 步备份的原厂 boot），或刷官方固件包中的 `boot.img`。

---

## 刷后自检

以下命令在 **root shell** 中执行（`adb shell` 后 `su`）：

```bash
uname -r                                                    # 5.15.211-g093e3da978e7
lsmod | tail -n +2 | wc -l                                  # 401（含 kernelsu）
mkdir -p /sys/kernel/security                               # Android 默认不挂载 securityfs
mount -t securityfs none /sys/kernel/security 2>/dev/null || true
cat /sys/kernel/security/lsm                                # 应含 baseband_guard
cat /proc/sys/net/ipv4/tcp_available_congestion_control     # reno bbr cubic
cat /sys/kernel/mm/lru_gen/enabled                          # 0x0003
dmesg | grep -iE 'disagrees about version|CFI failure|Unknown symbol'   # 应为空
```

---

## 注意事项 / 已知差异

- **版本串与官方不同是预期行为**：原厂模块带 `__versions`，比对 vermagic 时会忽略 release 段；真正决定驱动能否工作的是符号 CRC / KMI 兼容性，本内核 0 差异。
- **boot.img 不带原厂 AVB 签名**（vbmeta 及其余分区未改动）：需要保持 **Bootloader 解锁**；一旦回锁，boot 校验失败将无法启动本内核。
- **只替换 boot 分区的内核**：`vendor_dlkm`、`vendor_boot`、`init_boot`、`dtbo` 等均不触碰；系统 OTA 前建议先刷回原厂 boot，否则可能因 boot 校验失败导致 OTA 失败。
- **ThinLTO 与 Full LTO 生成代码等价**，不影响 genksyms CRC、CFI 类型哈希与 vermagic；切成 ThinLTO 只是为了在 GitHub Actions runner 的内存限制下稳定完成构建。
- **刷入后第一次开机**可能比平时略慢（系统服务首次初始化），属正常现象。

---

## 常见问题

- **刷完扬声器 / 摄像头失效？** 本内核目标系统是 HyperOS 3.0.304.0.WMKCNXM（Android 16 原厂 vendor）；其他 ROM / 版本可能因 vendor 模块 ABI 不同而异常。root 下先用 `dmesg | grep -iE 'disagrees about version|CFI failure|Unknown symbol'` 确认。
- **模块加载失败？** 先看 Release 里的 `abi-report-los.json`：`crc_mismatches` / `missing_symbols` 应为 0；若自行构建，可用 `los/scripts/check_module_abi.py` 重新生成报告对照。
- **怎么验证 BBG 生效？** root 下执行 `mkdir -p /sys/kernel/security && mount -t securityfs none /sys/kernel/security && cat /sys/kernel/security/lsm`（应含 `baseband_guard`）；再对一个受保护分区做无害测试，如 `chmod 640 /dev/block/by-name/persist`（只改设备节点权限位、不写分区数据），应在 dmesg 看到 `baseband_guard: deny setattr on protected partition`。
- **忘记备份原厂 boot？** 下载官方固件包（`boot.img`）后 `fastboot flash boot boot.img`，或使用 9008 线刷包恢复。

---

## 模块来源（源码 / 补丁 / 工具链）

本内核**所有代码与补丁均来自公开来源**，构建脚本自动下载并校验；本仓库不修改第三方源码分发的许可证。

| 类别 | 项目 |
|---|---|
| 内核源码 | [LineageOS/android_kernel_xiaomi_sm8550](https://github.com/LineageOS/android_kernel_xiaomi_sm8550) `lineage-23.2` @ `093e3da978e7b954d041a261d40975957c7fe6f1`（sha256 记录于 `los/config/sources.lock.json`） |
| 工具链 | AOSP Clang r563880c / 21.0.0，`platform/prebuilts/clang/host/linux-x86` @ `9916fb51ccb914d62d35ad9a7b9b21d2ef046928` |
| SYSVIPC kABI padding | [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) 官方 GKI patch |
| BBG 防格机 | [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) @ `48d9fdea643bcb41d204541400e9d8656b97a54f` |
| 调度 / 内存 / 定时器优化 | 社区常见 5.15 优化补丁（已逐个核对 kABI 安全），见 `los/patches/0020`–`0024` |
| AnyKernel3 模板 | [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) @ `c072981836cd3ee46ad52a5f2cba76ecb927cb1b` |
| boot.img 打包 | `los/scripts/make_bootimg.py`（Android boot header v4） |

**原厂组件**：`vendor_dlkm` / `vendor_boot` / `init_boot` / `dtbo` 等均原样保留，仅替换 boot 分区的内核 Image；原厂 400+ 模块按原方式工作，KernelSU 以 LKM 模式加载 `kernelsu` 模块（非本内核内置）。

**许可**

- 本仓库自行编写的构建脚本、内核配置与 `tools/` 辅助脚本以 **GPL-2.0-only** 发布（脚本文件头带 SPDX 标识；与内核源码及补丁许可保持一致，避免同仓库混合许可带来的合规歧义），完整许可文本见 [`LICENSE`](LICENSE)；
- 内核源码与 `los/patches/` 中的补丁为**第三方上游作品**（作者 / 来源见各补丁头），版权归各自作者，按其原始许可证（GPL-2.0 等）分发；
- 本仓库仅做源码下载、打补丁与构建编排，不修改第三方源码分发的许可证。

---

## 自行构建

- CI 工作流：`.github/workflows/build-los.yml`（push 修改 `los/**` 自动触发；ThinLTO，约 20 分钟）
- 构建脚本：`los/scripts/{prepare-runner,prepare,build,package}.sh`
- 版本锁定：`los/config/sources.lock.json`；设备基线配置：`los/config/device-baseline.config`
- 本地辅助工具：`tools/`（流水线监控、产物校验、设备验收脚本）
- 交接 / 踩坑记录：[`HANDOFF.md`](HANDOFF.md)
- 云端 runner 自带外网，**不需要**本地开代理

---

## 变更记录

- **2026-11-26 — `k60p-kernel-los-v1`**：首个 LOS 基线版本（5.15.211 + Droidspaces + BBG + 游戏优化，ThinLTO 构建）；
  实机验证：扬声器 / 麦克风 / 摄像头 / WiFi / 蜂窝 / 充电 / 120Hz / KernelSU LKM / BBG / Droidspaces 全部通过，内核模块 0 加载失败。

---

## 致谢

感谢 Google Android Common Kernel、LineageOS、Droidspaces、Baseband-guard、AnyKernel3 等所有上游开源项目与作者。

---

**本内核由 deepseek v4.1flash 开发。**
