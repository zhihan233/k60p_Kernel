# HANDOFF（2026-11-26 18:40 更新）— LOS ThinLTO 构建 ✅ 成功，等待实机验证

## 一句话状态
**ThinLTO run 4 `45797343370` 全绿**（build 16.5 分钟完成，总时长 ~20 分钟）。
**ABI 关键指标：401 模块 / 3971 符号 / `crc_mismatches=0` / `missing_symbols=0` / `unclassified=0`**
→ 厂商 vendor 模块应能干净加载。产物已从 Release `k60p-kernel-los-v1` 下载并校验通过
（本地 `deliver/`），下一步：**交用户 `fastboot boot boot-los.img` 实测**（先别 flash）。

## 18:40 构建结果（run 4）
- commit `8a94029` → workflow `build-los` run 4 `45797343370`
- 步骤耗时：prepare-runner 2.5m → restore cache 24s → **prepare 43s**（缓存命中 clang；
  源码+7 补丁全部应用）→ swap 0s → **build 16m35s（ThinLTO）** → package 5s →
  publish 6s → artifacts 4s，全部 success
- `abi-report-los.json`：`modules=401, matched_symbols=3971, crc_mismatches=[],
  not_in_kernel_symvers=573`（这 573 是**由其他 vendor 模块导出**的符号，如
  `__devm_regmap_init_swr`/`__gpr_driver_register`/`__traceiter_*`，属正常；
  `unclassified_missing_imports=0`, `missing_symbols=0`）
- `build-los.json`：kernel_release `5.15.211-g093e3da978e7`，ThinLTO 注明，hash 与 Release 一致
- 产物校验（`tools/check_boot.py`）：
  - `boot-los.img` 43,315,200 B，magic `ANDROID!`，header v4 / header_size 1584，
    kernel_size 43,309,568，ramdisk 0，内嵌版本串 `5.15.211-g093e3da978e7`，
    sha256 `bf6db3cc…953f` 与 `SHA256SUMS-los` 一致
  - `ak3-los.zip` 22,597,425 B（sha256 `b1819b07…9eb6` ✓）、`Image-los` 43,309,568 B
    （sha256 `865c9800…c4a7` ✓）
- kernel config 抽查：`LTO_CLANG_THIN=y`/`FULL` off、CFI/MODVERSIONS/KASAN_HW_TAGS/SCS 保留、
  `CONFIG_BBG=y` + LSM 含 `baseband_guard`、SYSVIPC/POSIX_MQUEUE/各类 NS/ipset/macvlan/tmpfs
  全 y、`DEFAULT_FQ_CODEL=y`、CAKE/FQ_CODEL/BBR=y、`LRU_GEN_ENABLED=y`、
  `TRIM_UNUSED_KSYMS` off
- 本地调试设施：`tools/monitor_run.ps1`（用 job 页面 HTML 轮询 step 状态，无需 API 限额）、
  `tools/check_boot.py`、`tools/fetch_release.ps1`、`tools/parse_actions.py`

## 当前下一步（等用户实测）
1. 用户 `fastboot boot boot-los.img`（**先别 flash**，临时引导重启即回官方）
2. 重点验证：**扬声器、摄像头（前后/录像）**、WiFi、充电/电池、BBG
   （`cat /sys/kernel/security/lsm` 含 `baseband_guard`）、Droidspaces 运行、KernelSU root
3. adb 检查：`su -c "lsmod | wc -l"` ≈ 402；
   `dmesg | grep -iE 'disagrees about version|CFI failure|Unknown symbol'` 应空
   - adb：`R:\platform-tools\adb.exe`（设备当前官方内核；offline 时 kill-server/start-server/reconnect offline）
4. 通过后：`fastboot flash boot boot-los.img` 永久刷入（也可用 `ak3-los.zip` 在 KernelSU/rec 里刷）；
   再更新 README 为 LOS 基线 + Release 链接，清理 `.debug/`、`debug-run.yml`、`artifacts-stockref`
   分支、旧 ACK 流水线与 Release
5. 若实机有问题：先看 `dmesg | grep -iE 'disagrees|CFI|Unknown symbol|avc:'`；
   音频/摄像头问题优先查 LOS 基线本身是否含对应 vendor 驱动配置（`kernel-los.config` 在 deliver/）


## 18:01 相对 14:00 的改动
- `los/scripts/build.sh`：`cp config/device-baseline.config out/.config` 后，对
  `kernel/arch/arm64/configs/gki_defconfig` 和 `out/.config` 执行
  `--enable LTO_CLANG_THIN` / `--disable LTO_CLANG_FULL`；
  自检断言改为 `LTO=y, LTO_CLANG=y, LTO_CLANG_THIN=y, LTO_CLANG_FULL!=y`
  （`CONFIG_LTO_CLANG_FULL` 已从 baseline 相等断言列表移除）；
  `build-los.json` 的 features 增加 `lto: ThinLTO ...` 说明
- `.github/workflows/build-los.yml`：swap 步骤改名「LTO link / swap safety」，磁盘不足时
  **跳过 swap 不硬失败**（ThinLTO 内存需求小）；其余不变
- 原因：run 3 `45755782891` prepare 全部成功，但 build 跑到第 68 分钟失败、`gh run view
  --log-failed` 返回 "log not found" → runner 失联（Full LTO OOM），不是代码错误
- ThinLTO 与 Full LTO 生成代码等价，**不影响** genksyms CRC / CFI 类型哈希 / vermagic

## 当前关键进度（14:00 起的既有事实）
- LOS 流水线（`los/**` + `.github/workflows/build-los.yml`）已完整推送并跑通 prepare
  （源码/工具链/7 个补丁全部干净应用）
- `los/config/sources.lock.json`：LineageOS `android_kernel_xiaomi_sm8550` branch
  `lineage-23.2` commit `093e3da978e7b954d041a261d40975957c7fe6f1`，release
  `5.15.211-g093e3da978e7`，工具链 clang r563880c
- 最近失败：run 3 `45755782891`（commit `02ea103`）— 见上；run 2 是下载截断（已修）；run 1 是补丁 strip 参数
- Release 目标：`k60p-kernel-los-v1`（成功自动上传 boot-los.img / ak3-los.zip / Image-los /
  SHA256SUMS-los / abi-report-los.json / build-los.json / kernel-los.config）
- 本次构建后若成功：验证 ABI → 让用户测扬声器/摄像头/WiFi/充电/BBG/Droidspaces/KernelSU

## 构建完成后验证步骤
1. `https://github.com/zhihan233/k60p_Kernel/releases/download/k60p-kernel-los-v1/<file>` 下载
   `boot-los.img`、`ak3-los.zip`、`abi-report-los.json`、`build-los.json`（有代理/直连都试）
2. **关键**：`abi-report-los.json` 的 `crc_mismatches` 是否 **0**、
   `not_in_kernel_symvers` / `unclassified_missing_imports` 是否正常；
   `status-los.txt`（在 artifacts / build log 里）应为 `abi=OK`
3. 校验 boot header v4 / kernel_size / 版本串 `5.15.211-g093e3da978e7`
   （与官方 `5.15.194-...` 不同是**预期**：vendor 模块带 CRC 会忽略 release 段；
   但**必须确认 lsmod=402 且无 disagrees**）
4. 交用户 `fastboot boot boot-los.img`（**先别 flash**）：扬声器、摄像头、WiFi、充电、
   BBG（`cat /sys/kernel/security/lsm` 含 baseband_guard）、Droidspaces、KernelSU root（LKM）
5. adb 检查：`su -c "lsmod | wc -l"` ≈ 402；
   `dmesg | grep -iE 'disagrees about version|CFI failure|Unknown symbol'` 应为空
   - adb：`R:\platform-tools\adb.exe`（设备当前官方内核；offline 时 kill-server/start-server/reconnect offline）

## 失败排查（本次若再失败）
- 看 step 级状态/日志：写 `.debug/run_id.txt`（run id）→ push → 等 ~1 分钟 →
  `git fetch origin debug-logs` → `git show FETCH_HEAD:out/run-<id>.json`（jobs/steps）、
  `git show FETCH_HEAD:out/run-<id>-failed.log`（失败日志）
  （debug-run workflow 为临时调试设施，全部完成后删除 `.debug/` 和该 workflow）
- 查 run 列表（HTML，避开 API 限额）：`Invoke-WebRequest
  https://github.com/zhihan233/k60p_Kernel/actions?x=$(Get-Random) -OutFile work/actions.html`
  然后 `python tools/parse_actions.py`
- 可能原因：内存（减 `-j` / JOBS 环境变量）、编译错误（B 计划：去掉 BBG/游戏补丁逐个排查）
- push（代理没开时直连）：`git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push origin main`
  （偶发 DNS 失败，重试即可；`ssh.github.com` 正常解析到 20.205.243.160）

## 背景事实（已确认，避免走回头路）
- 官方 HyperOS 3.0.304 内核是小米用自己 5.15.78 vendor 树（clang r450784e）编的、伪装 GKI 版本串；
  公开源码 MiCode `socrates-t-oss` 只有 5.15.41 → 无法复现官方内核 ABI
- 我们的 ACK 5.15.194 内核（v3/v4）能加载 402 模块但**扬声器/摄像头失效**（ABI 不兼容）
- 所以改用 LineageOS 内核（同 QCOM msm-kernel 血统，已有实机成功先例：402 模块、0 ABI mismatch）
- 官方 boot 已由用户刷回，设备当前为官方系统
- 旧 ACK 流水线：`config/`、`scripts/`、`patches/`、`.github/workflows/build.yml`（只在改动
  这些目录时触发，LOS 工作不会触发）；产物 Release `k60p-kernel-v4` 等，勿作最终交付
- 待清理（LOS 验证通过后）：`.debug/`、`debug-run.yml`、`artifacts-stockref` 分支、
  旧 ACK 流水线与 Release、旧工作分支；更新 README 为 LOS 基线说明 + 最新 Release 链接
