# K60 Pro (socrates) 定制内核 — 构建说明（最终版）

设备：Redmi K60 Pro / socrates / SM8550 (kalama) / HyperOS 3.0.304.0.WMKCNXM (Android 16)
成品：Release `k60p-kernel-v3`（boot-gaming.img / boot-standard.img / ak3-*.zip）
最终构建：GitHub Actions run `45591220514`，commit `8e7a7cc`

## 1. 源码与版本串

| 项目 | 值 |
|---|---|
| 内核源码 | Google kernel/common，精确提交 `f4321180a3973d19b626b3eef51871199e4e1fac`（原厂内核 banner 里的 `-00019-gf4321180a397`） |
| 下载方式 | `https://android.googlesource.com/kernel/common/+archive/f4321180a397....tar.gz`（Gitiles 归档，解压不带 --strip-components） |
| 版本串 | `5.15.194-android13-8-00019-gf4321180a397-ab15212794`（必须与原厂一致，否则 vendor 模块/KernelSU LKM 拒载） |
| 复现方式 | `LOCALVERSION=-android13-8` + `.scmversion=-00019-gf4321180a397` + `BUILD_NUMBER=15212794` |
| 工具链 | AOSP clang `r563880c` (21.0.0)，`LLVM=1 LLVM_IAS=1` |

## 2. 功能与配置

- Droidspaces（GKI 版）：SYSVIPC / POSIX_MQUEUE / IPC_NS / PID_NS / USER_NS / DEVTMPFS /
  NETFILTER_XT_MATCH_ADDRTYPE / MACVLAN / IP6_NF_NAT / IP6_NF_TARGET_MASQUERADE / ipset 等，
  加官方 `SYSVIPC kABI padding` 补丁（task_struct 槽 6/7/8）。
  不开 CFS_BANDWIDTH / CGROUP_PIDS（会破 kABI）。
- BBG（Baseband-guard）`vc-teahouse/Baseband-guard @48d9fde`，`CONFIG_BBG=y`，
  `CONFIG_LSM` 加 `baseband_guard`，默认不拦 boot/recovery。
- 游戏优化：gaming 变体 BBRv3 默认拥塞控制 + fq_codel + MGLRU 默认开 + sched/dcache/
  int_sqrt/clear_page/alarmtimer 小优化；standard 变体 BBR + fq_codel + MGLRU。
- 保持原厂：KASAN_HW_TAGS / CFI_CLANG / SHADOW_CALL_STACK / MODVERSIONS / DEBUG_INFO_BTF /
  MODULE_SIG 不变。
- **LTO 用 ThinLTO**：Full LTO 链接在 GitHub 共享 runner 上会 OOM（多次
  "hosted runner lost communication"）；ThinLTO 与 CFI/KMI 兼容，不影响 genksyms CRC /
  vermagic / 模块加载。

## 3. 模块 CRC 兼容处理（关键）

自编译内核与原厂预编译 vendor 模块存在约 350 个导出符号的 genksyms CRC 数值差异
（**符号无缺失**，已用 tag194/f432 × clang14/21 四组实验确认是构建环境差异）。
`patches/common/0025-module-ignore-crc.patch` 让 `kernel/module.c:check_version()`
跳过 CRC 数值比对，从而原厂 400+ 模块 + init_boot 里的 KernelSU/SukiSU 都能加载。
注意：`return 1;` 必须放在函数声明之后（否则 `-Wdeclaration-after-statement` Werror 构建失败）。

## 4. 云端重建流程

push 到 `main` 且改动命中 `.github/workflows/build.yml` 的 paths（`config/**`、
`patches/**`、`scripts/**`）时自动触发矩阵构建（standard + gaming），流程：
prepare-runner → 恢复/保存 clang cache → prepare（下载源码/工具链、打补丁、生成 KMI 白名单）→
分配 swap → build.sh（配置自检、make Image+modules、vermagic 断言、CRC 报告）→
package.sh（boot.img header v4 + AK3 zip + RELEASE 说明）→ publish-variant.sh（发 Release
`k60p-kernel-v3`，`--clobber`）→ artifacts 分支存档。

## 5. 产物校验要点

- boot.img：`ANDROID!` header v4、kernel_size == Image 大小、ramdisk=0、signature=0
- Image banner 必须等于原厂版本串
- `build-<variant>.json` 的 `ci_commit` 为当次构建 commit
- `SHA256SUMS-*` 与文件一致
- `abi-report-*.json`：`missing=0`、`unclassified=0`（CRC 数值差异由第 3 节处理）

## 6. 刷机

见 Release 内的 README.md：先 `fastboot boot boot-gaming.img` 验证，再
`fastboot flash boot boot-gaming.img`；回滚用原厂 boot.img。

## 7. 历史实验（已清理）

`.latest/`（5.15.226 变体）、`probe-latest.yml`、`build-latest.yml`、`rescue.yml`、
`abi-probe.yml`、`build-ab.yml`、`collect-run.yml` 均已删除，避免误触发无用构建。
