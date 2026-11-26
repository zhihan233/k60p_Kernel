# HANDOFF — K60 Pro (socrates) 5.15 定制内核（2026-11-26 19:25）

## 状态：✅ 构建 + 实机验证完成，等待用户自行永久刷入

- **交付 Release**：`k60p-kernel-los-v1` — https://github.com/zhihan233/k60p_Kernel/releases/tag/k60p-kernel-los-v1
- **内核**：LineageOS `android_kernel_xiaomi_sm8550` `lineage-23.2` @ `093e3da978e7`，Linux **5.15.211**
  - 版本串 `5.15.211-g093e3da978e7`，clang r563880c (21.0.0)，ThinLTO + CFI + MODVERSIONS + KASAN_HW_TAGS
- **ABI**：401 个厂商模块全部加载，`crc_mismatches = 0`、`missing_symbols = 0`、`unclassified = 0`
  （3971 个导入符号全部 CRC 一致；「401 vs 404 个 .ko」的差集只是 debug/test 模块与其它机型 WiFi 模块，
  `kiwi_v2` 就是 `qca_cld3_kiwi_v2.ko` 的模块名，`kernelsu` 为 KernelSU LKM 额外加载）
- **本地产物** `deliver/`（gitignore，未入库）：
  - `boot-los.img` 43,315,200 B，sha256 `bf6db3cc104de7293ca0fa846998ddcd9e8f2fd07ff7e75d7dce679348df953f`
  - `ak3-los.zip` 22,597,425 B，sha256 `b1819b07cf26c4ba26db5f607620f5e12f4504a57201e1c40180d104d6129eb6`
  - `stock-boot_a.img`：**原厂 boot_a 完整备份**（192MB 分区镜像，sha256 `5364ec15…250e`，
    版本串 `5.15.194-android13-8-00019-gf4321180a397-ab15212794`），回滚用
  - `Image-los` / `kernel-los.config` / `SHA256SUMS-los` / `abi-report-los.json` / `build-los.json`
- **刷入方式**（用户自行执行，**先临时 `fastboot boot` 再 `fastboot flash boot`**）：
  ```bash
  adb reboot bootloader
  fastboot boot boot-los.img      # 临时验证
  fastboot flash boot boot-los.img
  fastboot reboot
  # 回滚：fastboot flash boot stock-boot_a.img
  ```
  构建成功即自动发布 Release（`build-los` workflow 的 publish 步骤），本地 `deliver/` 只是缓存。

## 实机验证结果（2026-11-26，`fastboot boot` 临时启动，HyperOS 3.0.304 原厂系统）

- 人参与的测试（用户确认）：**扬声器 / 麦克风 / 摄像头（前后+录像）全部正常**
- 终端内测试（agent 完成，脚本 `tools/device_test{,2,3,4,5,6}.sh`）：
  - KernelSU LKM root：`su -c id` → `uid=0 ... context=u:r:ksu:s0`；ksud 3.3.1；`kernelsu` 模块已加载
  - 内核模块：`/proc/modules` = 401；dmesg 中 `disagrees about version / CFI failure / Unknown symbol /
    invalid module format` 计数全 0；`WARNING/BUG/Oops/Call trace/panic` 计数全 0；taint 仅来自厂商 out-of-tree 模块
  - **BBG 防格机**（功能实测）：`/sys/kernel/security/lsm = capability,safesetid,selinux,baseband_guard`
    （securityfs 默认未挂载，需 `mount -t securityfs none /sys/kernel/security`）；
    root(`u:r:ksu:s0`) 下 `chmod` 受保护分区（`persist`、`modem_a`）→ `Operation not permitted` +
    dmesg `baseband_guard: deny setattr on protected partition ...`；白名单分区 `boot_a` 正常放行
    （测试只改设备节点权限位、无任何分区数据写入；BBG 保护列表见 `los/patches/0010-baseband-guard-5.15.patch`）
  - 网络：WiFi `wlan0` 11ax 2401Mbps、RSSI -18、ping 0% 丢包；蜂窝中国移动 NR_SA IN_SERVICE
  - 充电：`status=Charging`、`current_now≈379mA`、`constant_charge_current=5A`、温度 ~24°C
  - 音频/摄像头：`kalama-mtp-snd-card`、audioserver/audio HAL、`/dev/video*`、cameraserver + vendor provider 全部在跑
  - 显示 1440×3200 60/90/120Hz；蓝牙协议栈运行；Droidspaces app 运行、`unshare -Ur`/`-Urmpf` rc=0、cgroup v2 可用
  - MGLRU `0x0003`；默认队列 `fq_codel`；`tcp_available_congestion_control = reno bbr cubic`；zram0 12GB (lzo-rle)

## 仓库结构（清理后）

```
los/                  # LineageOS 基线流水线（唯一构建流水线）
  config/             # sources.lock.json（内核/工具链/补丁版本锁）、device-baseline.config、droidspaces/extras config、anykernel.sh
  patches/            # 0001 sysvipc kABI padding, 0010 BBG, 0020–0024 调度/内存小补丁（均为第三方上游补丁，作者见文件头）
  scripts/            # prepare-runner / prepare / build / package / make_bootimg / check_module_abi / elf_versions / verify_git_tree
  evidence/           # vendor-module-versions.json（404 个原厂模块的导入符号 CRC 证据）
.github/workflows/build-los.yml   # 唯一 CI：push 改 los/** 触发，ThinLTO 全流程（prepare→build→package→release）
tools/                # 本地辅助：parse_actions.py / monitor_run.ps1（HTML 轮询 step 状态）/ check_boot.py /
                      # fetch_release.ps1 / analyze_device.py / device_test*.sh
LICENSE               # GPL-2.0-only 许可全文（脚本/配置带 SPDX 标识；第三方源码与补丁按其原始许可）
HANDOFF.md            # 本文件
README.md             # 项目说明（LOS 基线、验证结果、刷入、自检）
```
> 旧 ACK 流水线（`config/`、`scripts/`、`patches/`、`docs/`、`build.yml`）、`.debug/` + `debug-run.yml`
> 已于 19:25 删除；远端 `artifacts-gaming/standard/stockref`、`debug-logs` 分支与 `k60p-kernel-v3/v4` tag 已删除。
> 若 GitHub Releases 页面仍能看到 v3/v4（无 API token，无法本地删 Release 对象），网页点 Delete 即可。

## 排障 / 重建速查

- 重新构建：`git push` 修改 `los/**` 即触发；或 Actions 页面 `workflow_dispatch`
- 监控（无需 GitHub API 限额）：`python tools/monitor_run.ps1` 用 job 页面 HTML 轮询 step；
  或 `Invoke-WebRequest https://github.com/zhihan233/k60p_Kernel/actions?x=$(Get-Random) -OutFile work/actions.html`
  + `python tools/parse_actions.py`
- 下载 Release：`tools/fetch_release.ps1`（curl，必要时加 `-x http://127.0.0.1:7897`；大文件慢是正常）
- 校验 boot 镜像：`python tools/check_boot.py deliver/boot-los.img`（header v4 / kernel_size / 版本串 / sha256）
- 设备测试：`adb push tools/device_test.sh /data/local/tmp/` → `adb shell "su -c 'sh /data/local/tmp/device_test.sh'"`
  → `adb pull /data/local/tmp/kern-test`
- adb/fastboot：`R:\platform-tools\{adb,fastboot}.exe`（adb offline 时 kill-server + start-server + reconnect offline）
- push（代理没开时直连）：`git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push origin main`
  （偶发 DNS 失败重试；`ssh.github.com` → 20.205.243.160）
- 若构建再遇 runner OOM：确认 `los/scripts/build.sh` 的 ThinLTO 切换仍在（`LTO_CLANG_THIN=y` / `FULL` off）

## 背景事实（避免走回头路）

- 官方 HyperOS 3.0.304 内核是小米用自己 5.15.78 vendor 树（clang r450784e）编的、伪装 GKI 版本串；
  公开源码 MiCode `socrates-t-oss` 只有 5.15.41 → **无法用 ACK 复现官方 ABI**
  （此前 ACK 5.15.194 的 v3/v4 能加载 402 模块但扬声器/摄像头失效，已废弃）
- LineageOS sm8550 内核与官方同属 QCOM msm-kernel vendor 树，kABI/结构体布局一致 → 0 CRC mismatch、驱动全正常
- 版本串与官方不同是**预期**：带 `__versions` 的模块比对 vermagic 时忽略 release 段；决定驱动的是 CRC/KMI
- 可选后续：BBRv3 backport（当前内核自带 BBR v1）、游戏调度增强、待机/suspend 长稳测试
