# HANDOFF（2026-11-26 14:00 暂停，18:00 继续）— LineageOS 内核构建进行中

## 一句话状态
LOS 基线流水线（`los/`）已经**跑通 prepare（源码/工具链/全部补丁成功应用）**，但 Full LTO 构建在
第 68 分钟失败（runner 日志不可用，大概率是 **Full LTO 链接 OOM / runner lost communication**）。
18:00 回来第一件事：**把 LOS 构建切成 ThinLTO** 重新跑，然后验证 ABI 报告是否 0 mismatch。

## 当前关键进度
- LOS 流水线已全部写完并推送（`los/` 目录 + `.github/workflows/build-los.yml`），HEAD ~`8f1290e`
- 最近一次构建：**run 3 `45755782891`**（commit `02ea103`）
  - 结果：failure，1h8m5s；**prepare 步骤成功**（源码/工具链/7 个补丁全部应用 ✓）
  - build 步骤从 04:40:43 UTC 开始一直跑到 ~05:39 UTC 后失败，`gh run view --log-failed`
    返回 "log not found" → runner 失联（典型 Full LTO 内存不足），不是代码错误
- `config/sources.lock.json`（los 下）描述：LineageOS `android_kernel_xiaomi_sm8550`
  branch `lineage-23.2` commit `093e3da978e7b954d041a261d40975957c7fe6f1`，
  release `5.15.211-g093e3da978e7`，工具链 clang r563880c，Full LTO baseline
- Release 目标：`k60p-kernel-los-v1`（成功后自动发布 boot-los.img / ak3-los.zip 等）

## 18:00 继续步骤
1. **切 ThinLTO 重编**（改 `los/scripts/build.sh`）：
   - 在 `cp config/device-baseline.config out/.config` 之后加：
     ```bash
     for f in kernel/arch/arm64/configs/gki_defconfig out/.config; do
       kernel/scripts/config --file "$f" --enable LTO_CLANG_THIN
       kernel/scripts/config --file "$f" --disable LTO_CLANG_FULL
     done
     ```
   - 自检断言改成：`CONFIG_LTO_CLANG_THIN == y` 且 `CONFIG_LTO_CLANG_FULL != y`
     （当前脚本还按 FULL==baseline 断言，会失败，必须改）
   - build.json features 里注明 "ThinLTO (CI 稳定性；等价 ABI)"
2. commit & push（只改 `los/**` → 自动触发 build-los run 4，约 25-40 分钟）
3. 构建完成后：
   - `gh` 会自动发布 Release `k60p-kernel-los-v1`
   - 下载 `boot-los.img`、`ak3-los.zip`、`abi-report-los.json`、`build-los.json`
   - **关键检查**：`abi-report-los.json` 的 `crc_mismatches` 是否 **0**、
     `not_in_kernel_symvers` / `unclassified_missing_imports` 是否正常；
     `status-los.txt` 应为 `abi=OK`（build.sh 里期望 0 mismatch）
   - 下载与校验方法：`https://github.com/zhihan233/k60p_Kernel/releases/download/k60p-kernel-los-v1/<file>`
     ，用 `make_bootimg.py` 逻辑校验 header v4 / kernel_size / 版本串
     （版本串应为 `5.15.211-g093e3da978e7`；与官方 `5.15.194-...` 不同是**预期**，
     vendor 模块带 CRC 会忽略 release 段；但**必须确认 lsmod=402 且无 disagrees**）
4. 交给用户 `fastboot boot boot-los.img` 测试（**先别 flash**）：
   - 重点：扬声器、摄像头、WiFi、充电、BBG（`cat /sys/kernel/security/lsm` 含 baseband_guard）、
     Droidspaces Requirements 检查、KernelSU root（LKM 模式）
   - `adb shell su -c "lsmod | wc -l"` ≈ 402；`dmesg | grep -iE 'disagrees about version|CFI failure|Unknown symbol'` 应为空
   - adb：`R:\platform-tools\adb.exe`（设备当前官方内核；offline 时 kill-server/start-server/reconnect offline）
5. 如果 ThinLTO 构建还失败：看 debug 日志（见下），可能原因：内存（再减 `-j` / 加 swap）、
   编译错误（B 计划：去掉 BBG/游戏补丁逐个排查）

## 工具/命令速查
- 查 run 状态（HTML，避免 API 限额）：
  `Invoke-WebRequest https://github.com/zhihan233/k60p_Kernel/actions?x=1 -OutFile work\actions.html`
  然后 `python work\parse_actions.py`
- 看 step 级状态 / 失败日志：更新 `.debug/run_id.txt`（写 run id）→ push →
  等 ~1 分钟 → `git fetch origin debug-logs` →
  `git show FETCH_HEAD:out/run-<id>.json`（jobs/steps）、`out/run-<id>-failed.log`（失败日志）
  （debug-run workflow 是临时调试用，全部完成后应删除 `.debug/` 和该 workflow）
- push（代理没开时直连）：`git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push origin main`
- 本地启动/监控脚本都在 `work/`（parse_actions.py、verify_v3_final.py 等）

## 背景事实（已确认，避免走回头路）
- 官方 HyperOS 3.0.304 内核是小米用自己 5.15.78 vendor 树（clang r450784e）编的、伪装 GKI 版本串；
  公开源码 MiCode `socrates-t-oss` 只有 5.15.41 → 无法复现官方内核 ABI
- 我们的 ACK 5.15.194 内核（v3/v4）能加载 402 模块但**扬声器/摄像头失效**（ABI 不兼容）
- 所以改用 LineageOS 内核（同 QCOM msm-kernel 血统，已有实机成功先例：402 模块、0 ABI mismatch）
- 官方 boot 已由用户刷回，设备当前为官方系统
- 之前 ACK 流水线产物：Release `k60p-kernel-v4`（告警兼容模式，勿再作为最终交付）；
  `artifacts-stockref` 分支是 ACK 纯原厂配置实验的产物（可选后续查 ABI 对照，不影响 LOS 路线）
- 旧 ACK workflow（build.yml）仍在：只在改动 `config/**`、`patches/**`、`scripts/**`、
  `evidence/**` 时触发；LOS 工作只动 `los/**` 不会触发它

## 待清理（LOS 验证通过后）
- 删除临时调试设施：`.debug/`、`.github/workflows/debug-run.yml`、
  `.github/workflows/build-los.yml` 里的调试痕迹（可选）、`artifacts-stockref` 分支、
  旧的 ACK 流水线（`scripts/`、`config/`、`patches/`、`build.yml`）可按需归档/删除
- 更新仓库 README：改成 LOS 基线说明 + 最新 Release 链接
