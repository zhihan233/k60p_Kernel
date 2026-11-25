# Redmi K60 Pro (socrates) 5.15 定制内核

> [!WARNING]
> **⚠️ 刷机有风险，操作需谨慎！**
>
> - 刷入第三方内核**可能导致设备变砖、数据丢失、保修失效、无法开机或无法进入系统**。
> - 请务必先**完整备份**你的数据、boot 分区（以及 init_boot / vendor_boot），并确认 Bootloader 已解锁、自己有能力通过 fastboot / 9008 救砖。
> - **强烈建议先 `fastboot boot boot-gaming.img` 临时启动验证**，确认能正常开机、模块正常加载后再 `fastboot flash boot` 正式刷入。
> - 本内核按原厂配置构建并已在实机验证，但**作者不对任何直接或间接损失负责**；刷机即代表你自行承担全部风险。
> - 请勿在未解锁 / 有锁状态的设备上刷入；不同 ROM 版本之间可能存在兼容性差异。

---

## 项目简介

- **设备**：Redmi K60 Pro（代号 `socrates`，SM8550 / kalama，22127RK46C）
- **目标系统**：HyperOS 3.0.304.0.WMKCNXM（Android 16）
- **内核基线**：Android Common Kernel（GKI）5.15，`linux-5.15` 线
- **版本串**：`5.15.194-android13-8-00019-gf4321180a397-ab15212794`（与原厂完全一致，保证原厂 400+ vendor 模块与 KernelSU/SukiSU 可正常加载）
- **构建方式**：GitHub Actions 云端编译（本仓库 push 自动触发），不经本地交叉编译

**已包含功能**

1. **Droidspaces 容器支持**：SYSVIPC / POSIX_MQUEUE / IPC_NS / PID_NS / USER_NS / DEVTMPFS / MACVLAN / IPv6 NAT / ipset 等 GKI 版所需配置 + 官方 kABI padding 补丁
2. **BBG（Baseband-guard）防格机**：拦截对 modem/基带等关键分区和设备的未授权写入
3. **游戏优化**：gaming 版默认 **BBRv3** 拥塞控制 + `fq_codel` 队列 + MGLRU 默认开启 + 调度/内存小优化；standard 版为 BBR + 同套基础优化

---

## 模块来源（源码 / 补丁 / 工具链）

本内核**所有代码与补丁均来自公开来源**，构建脚本自动下载并校验；本仓库不修改第三方源码分发的许可证。

### 1. 内核源码
| 项目 | 来源 |
|---|---|
| Android GKI 5.15 内核（socrates 原厂对应的精确提交） | Google `kernel/common`，commit `f4321180a3973d19b626b3eef51871199e4e1fac` |
| 下载地址 | `https://android.googlesource.com/kernel/common/+archive/f4321180a397....tar.gz` |
| 说明 | 原厂内核 banner 含 `-00019-gf4321180a397`，即该提交；使用精确提交可保证行为与原厂 GKI 一致 |

### 2. 编译工具链
| 项目 | 来源 |
|---|---|
| AOSP Clang | `r563880c`（21.0.0），`platform/prebuilts/clang/host/linux-x86` commit `9916fb51ccb914d62d35ad9a7b9b21d2ef046928` |

### 3. 功能补丁
| 补丁 | 来源/作者 |
|---|---|
| SYSVIPC kABI padding（task_struct 槽 6/7/8） | [ravindu644/Droidspaces-OSS](https://github.com/ravindu644/Droidspaces-OSS)（官方 GKI 内核补丁） |
| BBG 防格机（Baseband-guard LSM） | [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) @ `48d9fdea643bcb41d204541400e9d8656b97a54f` |
| BBRv3 拥塞控制 | Google BBRv3（2023 版）Android 13-5.15 kABI 适配 backport |
| 调度/内存/定时器小优化（sched 扫描顺序、dcache 减压、int_sqrt、clear_page、alarmtimer） | 社区常见 5.15 内核优化补丁（已逐个核对 kABI 安全） |
| 模块 CRC 跳过（兼容原厂预编译 vendor 模块） | 本仓库自写补丁 `patches/common/0025-module-ignore-crc.patch` |

### 4. 打包工具
| 项目 | 来源 |
|---|---|
| AnyKernel3 刷机包模板 | [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) @ `c072981836cd3ee46ad52a5f2cba76ecb927cb1b`，按本设备（boot 分区、A/B 槽位）配置 |
| boot.img 打包 | 本仓库 `scripts/make_bootimg.py` 自实现（Android boot header v4，kernel 偏移 4096，无 ramdisk） |

### 5. 原厂组件（未修改、原样保留）
- `vendor_dlkm` 里的 400+ 个原厂内核模块来自 **HyperOS 3.0.304.0.WMKCNXM 固件**，本内核只替换 **boot 分区的内核 Image**，不触碰 vendor_boot / init_boot / dtbo / vendor_dlkm；
- 原厂模块签名、KernelSU/SukiSU（若已安装于 init_boot）均按原方式工作。

### 6. 开源许可
- 内核源码与各补丁版权归各自上游作者所有（GPL-2.0 等，详见各文件头）；
- 本仓库的构建脚本与自写补丁以 GPL-2.0 提供。

---

## 获取成品 / 刷入

- **Release 下载**：https://github.com/zhihan233/k60p_Kernel/releases/tag/k60p-kernel-v3
  - `boot-gaming.img`（推荐，游戏优化版）
  - `boot-standard.img`（保守版）
  - `ak3-gaming.zip` / `ak3-standard.zip`（AnyKernel3，可配合刷机 App 使用）
  - `Image-*.` / `SHA256SUMS-*` / `abi-report-*.json` / `kernel-*.config`

```bash
# 0) 备份原厂 boot（手机 root shell / Termux）
dd if=/dev/block/by-name/boot_a of=/sdcard/boot_backup.img

# 1) 关机 → 电源+音量下 进入 fastboot
fastboot devices

# 2) 先临时启动测试（不写分区，重启即恢复原系统）
fastboot boot boot-gaming.img

# 3) 确认能正常开机后再正式刷入
fastboot flash boot boot-gaming.img
fastboot reboot
```

**回滚**：`fastboot flash boot boot.img`（用你备份的原厂 boot.img 或官方固件包里的 boot.img）。

**刷后自检**

```bash
uname -r                                           # 应与原厂版本串一致
lsmod | wc -l                                      # 约 400
cat /sys/kernel/security/lsm | tr ',' '\n' | grep baseband   # 有 baseband_guard
cat /proc/sys/net/ipv4/tcp_congestion_control      # gaming 版 = bbr3
cat /sys/kernel/mm/lru_gen/enabled                 # MGLRU 已启用
dmesg | grep -iE 'unknown symbol|disagrees about version|CFI failure'
```

---

## 自行构建

- CI 工作流：`.github/workflows/build.yml`（matrix：standard + gaming，push 自动触发）
- 构建参数与流程详见 [`docs/BUILD-NOTES.md`](docs/BUILD-NOTES.md)
- 详细交接/踩坑记录见 [`docs/HANDOFF.md`](docs/HANDOFF.md)
- 云端 runner 自带外网，**不需要**本地开代理；本地仅用 git 操作仓库即可。

---

## 致谢

感谢 Google Android Common Kernel、Droidspaces、Baseband-guard、AnyKernel3 等所有上游开源项目与作者。

---

**本内核由 deepseek v4.1flash 开发。**
