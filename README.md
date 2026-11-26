# Redmi K60 Pro (socrates) 5.15 定制内核 — LineageOS 基线

> [!WARNING]
> **⚠️ 刷机有风险，操作需谨慎！**
>
> - 刷入第三方内核**可能导致设备变砖、数据丢失、保修失效、无法开机或无法进入系统**。
> - 请务必先**完整备份**你的数据与 boot 分区，确认 Bootloader 已解锁、自己有能力通过 fastboot / 9008 救砖。
> - **强烈建议先 `fastboot boot boot-los.img` 临时启动验证**，确认能正常开机、模块正常加载后再 `fastboot flash boot` 正式刷入。
> - 本内核已在实机验证（见下文「实机验证结果」），但**作者不对任何直接或间接损失负责**；刷机即代表你自行承担全部风险。
> - 请勿在未解锁 / 有锁状态的设备上刷入；不同 ROM 版本之间可能存在兼容性差异。

---

## 项目简介

- **设备**：Redmi K60 Pro（代号 `socrates`，SM8550 / kalama，22127RK46C）
- **目标系统**：HyperOS 3.0.304.0.WMKCNXM（Android 16，原厂 vendor / 400+ 原厂内核模块）
- **内核基线**：**LineageOS `android_kernel_xiaomi_sm8550`**（`lineage-23.2` 分支，commit `093e3da978e7`，Linux **5.15.211**）
  - 与官方内核同属高通 msm-kernel vendor 树血统，**kABI / 结构体布局与原厂 vendor 模块完全一致**
  - 实测：401 个原厂模块全部加载，`crc_mismatches = 0`、`missing_symbols = 0`，无 `disagrees about version` / `CFI failure`
- **版本串**：`5.15.211-g093e3da978e7`（与官方伪装的 `5.15.194-android13-8-...` 不同是预期行为——原厂模块带 `__versions`，比对 vermagic 时忽略 release 段；**决定驱动能否工作的是 CRC/KMI，本内核 0 差异**）
- **构建方式**：GitHub Actions 云端编译（push 自动触发），**ThinLTO**（CI runner 内存限制下与 Full LTO 生成代码等价，不影响 CRC/CFI/vermagic）

**已包含功能**

1. **Droidspaces 容器支持**：GKI 5.15 官方配置 + **SYSVIPC kABI padding（task_struct 槽 6/7/8）** 补丁；SYSVIPC / POSIX_MQUEUE / IPC_NS / PID_NS / USER_NS / NET_NS / UTS_NS / DEVTMPFS / TMPFS / MACVLAN / ipset / IPv6 NAT / NETFILTER_XT_MATCH_ADDRTYPE 等全部开启。
2. **BBG（Baseband-guard）防格机**：LSM 模块，拦截 `u:r:su / magisk / ksu` 等**非受信 root 进程**对 boot/baseband 等关键分区的写入、setattr 与破坏性 ioctl（`CONFIG_BBG=y`，boot/recovery 可在 `Kconfig` 中按需开启保护）。
3. **游戏/性能优化**：**MGLRU 默认开启**、默认队列 **fq_codel**（CAKE/FQ/FQ_CODEL 全量编译）、**BBR** 拥塞控制、CPU 扫描顺序优化（`sched-adjust-cpu-scan-order`）、dcache 减压、`clear_page` 16 字节对齐、`int_sqrt`、alarmtimer 唤醒最小化等小补丁。

---

## 实机验证结果（2026-11-26，`fastboot boot` 临时启动，HyperOS 3.0.304 原厂系统）

| 项目 | 结果 |
|---|---|
| 开机 / 系统启动 | ✅ 正常进入系统，无黑屏/重启 |
| 扬声器 / 麦克风 / 通话 | ✅ 用户实测正常 |
| 摄像头（前后 / 录像） | ✅ 用户实测正常 |
| WiFi / 网络 | ✅ `wlan0` 11ax 2401Mbps，ping 外网 0% 丢包 |
| 蜂窝网络 / 基带 | ✅ 中国移动 NR_SA 注册（IN_SERVICE），信号正常 |
| 充电 / 电池 | ✅ USB 充电、5A 充电电流、温度 24°C |
| 显示 / 触摸 | ✅ 1440×3200，60/90/**120Hz** 模式正常 |
| 蓝牙 | ✅ 协议栈服务运行（HAL + `com.android.bluetooth`） |
| KernelSU（LKM 模式） | ✅ `su` → `uid=0 ... context=u:r:ksu:s0`，ksud 3.3.1 |
| 原厂内核模块 | ✅ `/proc/modules` 401 个，**0 加载失败**，无 CRC/vermagic/CFI 报错 |
| **BBG 防格机** | ✅ `/sys/kernel/security/lsm` 含 `baseband_guard`；实测 `chmod` 受保护分区（`persist`/`modem_a`）→ `Operation not permitted` + dmesg `baseband_guard: deny setattr on protected partition`；白名单（`boot_a`）正常放行 |
| Droidspaces | ✅ App/守护进程运行；`unshare -Ur` / `unshare -Urmpf` 全部成功，cgroup v2 可用 |
| 内核稳定性 | ✅ `dmesg` 中 `WARNING/BUG/Oops/Call trace/panic` 计数均为 0 |
| MGLRU / 队列 / 拥塞控制 | ✅ `lru_gen/enabled=0x0003`、`fq_codel`、`bbr` 可用 |

---

## 模块来源（源码 / 补丁 / 工具链）

本内核**所有代码与补丁均来自公开来源**，构建脚本自动下载并校验；本仓库不修改第三方源码分发的许可证。

### 1. 内核源码
| 项目 | 来源 |
|---|---|
| 内核基线 | [LineageOS/android_kernel_xiaomi_sm8550](https://github.com/LineageOS/android_kernel_xiaomi_sm8550)，`lineage-23.2` @ `093e3da978e7b954d041a261d40975957c7fe6f1`（5.15.211） |
| 下载 | `https://codeload.github.com/LineageOS/android_kernel_xiaomi_sm8550/tar.gz/093e3da978e7...`（sha256 记录于 `los/config/sources.lock.json`） |

### 2. 编译工具链
| 项目 | 来源 |
|---|---|
| AOSP Clang r563880c（21.0.0） | `platform/prebuilts/clang/host/linux-x86` @ `9916fb51ccb914d62d35ad9a7b9b21d2ef046928` |

### 3. 功能补丁（`los/patches/`）
| 补丁 | 来源/作者 |
|---|---|
| SYSVIPC kABI padding（task_struct 槽 6/7/8） | [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS) 官方 GKI patch |
| BBG 防格机（Baseband-guard LSM） | [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) @ `48d9fdea643bcb41d204541400e9d8656b97a54f` |
| 调度/内存/定时器小优化（`sched-adjust-cpu-scan-order`、`dcache-reduce-cache-pressure`、`lib-int-sqrt`、`clear-page-16bytes-align`、`alarmtimer-minimise-wakeup-time`） | 社区常见 5.15 优化补丁（已逐个核对 kABI 安全） |

### 4. 打包工具
| 项目 | 来源 |
|---|---|
| AnyKernel3 模板 | [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) @ `c072981836cd3ee46ad52a5f2cba76ecb927cb1b`（`BOOT` 分区 + A/B 配置） |
| boot.img 打包 | `los/scripts/make_bootimg.py`（Android boot header v4，kernel 偏移 4096，无 ramdisk/signature） |

### 5. 原厂组件（未修改、原样保留）
- `vendor_dlkm` / `vendor_boot` / `init_boot` / `dtbo` 等**均不触碰**，只替换 boot 分区的内核 Image；
- 原厂 400+ 模块、原厂 AVB 与 KernelSU LKM 内核模块（`kernelsu.ko`）按原方式工作。

### 6. 开源许可
- 内核源码与各补丁版权归各自上游作者所有（GPL-2.0 等，详见各文件头）；
- 本仓库的构建脚本与自写补丁以 GPL-2.0 提供。

---

## 获取成品 / 刷入

- **Release**：https://github.com/zhihan233/k60p_Kernel/releases/tag/k60p-kernel-los-v1
  - `boot-los.img`（fastboot 用 boot 镜像）
  - `ak3-los.zip`（AnyKernel3 刷机包，可配合 KernelSU / 刷机 App 使用）
  - `Image-los` / `SHA256SUMS-los` / `abi-report-los.json` / `build-los.json` / `kernel-los.config`
- 本次构建校验值（与 Release `SHA256SUMS-los` 一致）：
  - `boot-los.img`：`bf6db3cc104de7293ca0fa846998ddcd9e8f2fd07ff7e75d7dce679348df953f`（43,315,200 B）
  - `ak3-los.zip`：`b1819b07cf26c4ba26db5f607620f5e12f4504a57201e1c40180d104d6129eb6`（22,597,425 B）

```bash
# 0) 备份原厂 boot（设备已 root，adb shell 内）
su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/Download/stock-boot_a.img bs=1M"

# 1) 进入 fastboot
adb reboot bootloader

# 2) 先临时启动测试（不写分区，重启即回原系统）
fastboot boot boot-los.img

# 3) 确认一切正常后再正式刷入
fastboot flash boot boot-los.img
fastboot reboot
```

**回滚**：`fastboot flash boot stock-boot_a.img`（原厂 boot 备份），或刷官方固件包中的 boot.img。

---

## 刷后自检

```bash
uname -r                                             # 5.15.211-g093e3da978e7
lsmod | wc -l                                        # 约 401
cat /sys/kernel/security/lsm                         # 含 baseband_guard
cat /proc/sys/net/ipv4/tcp_available_congestion_control   # reno bbr cubic
cat /sys/kernel/mm/lru_gen/enabled                   # 0x0003
dmesg | grep -iE 'disagrees about version|CFI failure|Unknown symbol'   # 应为空
```

---

## 自行构建

- CI 工作流：`.github/workflows/build-los.yml`（push 修改 `los/**` 自动触发，ThinLTO，约 20 分钟）
- 构建脚本：`los/scripts/{prepare-runner,prepare,build,package}.sh`
- 构建参数与版本锁定：`los/config/sources.lock.json`；设备基线配置：`los/config/device-baseline.config`
- 交接/踩坑记录：[`HANDOFF.md`](HANDOFF.md)
- 云端 runner 自带外网，**不需要**本地开代理

---

## 致谢

感谢 Google Android Common Kernel、LineageOS、Droidspaces、Baseband-guard、AnyKernel3 等所有上游开源项目与作者。

---

**本内核由 deepseek v4.1flash 开发。**
