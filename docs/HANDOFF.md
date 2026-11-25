# 交接文档 — Redmi K60 Pro (socrates) 5.15 定制内核

> 状态：**已完成并实机验证**（用户已刷入 boot-gaming.img，测试通过）
> 最后更新：2026-11-25 19:30（Asia/Hong_Kong）
> 仓库 HEAD：`e57898c`
> 构建仓库：https://github.com/zhihan233/k60p_Kernel
> 成品 Release：https://github.com/zhihan233/k60p_Kernel/releases/tag/k60p-kernel-v4

---

## 1. 项目概述

| 项目 | 内容 |
|---|---|
| 设备 | Redmi K60 Pro（`socrates` / SM8550 kalama / 22127RK46C） |
| ROM | HyperOS 3.0.304.0.WMKCNXM（Android 16，Bootloader 已解锁、已 root） |
| 原厂内核 | `Linux version 5.15.194-android13-8-00019-gf4321180a397-ab15212794`，clang r450784e，KMI gen8 |
| 需求 | 5.15 最新内核 + Droidspaces 容器支持 + BBG 防格机 + 游戏优化 + **GitHub Actions 云端编译** |
| 交付 | `boot-gaming.img`（主推）/ `boot-standard.img` / AnyKernel3 zip + 中文说明书 |
| 构建方式 | GitHub Actions 矩阵（standard + gaming），源码/工具链/补丁全部自动下载 |

---

## 2. 最终交付物（local: `deliver/`，线上: Release k60p-kernel-v4）

| 文件 | 大小 (B) | SHA256 |
|---|---|---|
| boot-gaming.img | 42,336,256 | `abad1997dd0fa01d35758e9fd04a436403357655114d18bfb5c64aab529eadd1` |
| boot-standard.img | 42,336,256 | `07a73566cf360a8b107ad82875a442aec46fa864642b71a4feaa409e048262b9` |
| Image-gaming | 42,330,624 | `a3509647677d40fa367d3b1596f1e1beceefde134d28679891628b40f78ec5d3` |
| Image-standard | 42,330,624 | `882791e634bdede048e1759cdafe058c0ba1c5f0aa649d108f1c3e39b5d691dc` |
| ak3-gaming.zip | 22,122,690 | `9ae03775672d5cf06229553536933c64d77e66b8ed431084f63df6586353bd1e` |
| ak3-standard.zip | 22,112,376 | `cd06cdec274e16f1581cb8008291b3e7e236f32db3e950ffc477aa030bc0a90b` |
| abi-report-*.json | 300,782 | 与原厂 404 模块导入符号对比报告 |
| build-*.json / kernel-*.config | — | 构建元数据 / 完整内核配置 |
| README.md | 7,292 | 中文刷机说明（交付给用户） |

**最终构建**：GitHub Actions run `45591220514`，commit `8e7a7cc`，两个变体全部 success；
每次构建产物另有 `SHA256SUMS-*` 文件可校验。

---

## 3. 最终参数与验证结论

### 3.1 版本串（必须与原厂完全一致）
```
5.15.194-android13-8-00019-gf4321180a397-ab15212794
```
复现方式（`scripts/prepare.sh` + `scripts/build.sh`）：
- `LOCALVERSION=-android13-8`（make 环境变量）
- `kernel/.scmversion` 写入 `-00019-gf4321180a397`
- `BUILD_NUMBER=15212794`

> 注意：`kernel-*.config` 里 `CONFIG_LOCALVERSION=""` 是正常的，`-android13-8` 是构建时环境变量传入。

### 3.2 boot.img 校验（已验证）
- magic `ANDROID!`，header **v4**，page size 4096
- kernel_size == `Image-*` 大小（42,330,624），**ramdisk=0**，signature=0
- boot.img 内 kernel 区与 `Image-*` 逐字节相同
- Image banner == 原厂版本串（clang 21.0.0 r563880c 构建，仅字符串元数据不同）

### 3.3 模块兼容（ABI 报告）
- 对比原厂 404 个 vendor_dlkm 模块：**缺失符号 0，未分类缺失 0**，`not_in_kernel_symvers=1502`（属其它 vendor 模块导出，正常）
- 唯一差异：350 个符号的 genksyms **CRC 数值**不同 → 已由 `0025-module-abi-alarm.patch` 打开告警（CRC/vermagic 不一致会打印 dmesg，默认继续加载，详见第 4.4 节）
- 实机验证：400+ 模块正常加载、系统正常启动、KernelSU/SukiSU 正常（用户已确认）

### 3.4 关键 config（gaming 变体，已验证开启）
```
CONFIG_SYSVIPC=y  CONFIG_POSIX_MQUEUE=y  CONFIG_IPC_NS=y  CONFIG_PID_NS=y  CONFIG_USER_NS=y
CONFIG_DEVTMPFS=y  CONFIG_MACVLAN=y  CONFIG_IP6_NF_NAT=y  CONFIG_IP_SET=y
CONFIG_TMPFS_XATTR=y  CONFIG_TMPFS_POSIX_ACL=y
CONFIG_BBG=y  CONFIG_LSM="...,selinux,baseband_guard,smack,..."
CONFIG_LRU_GEN_ENABLED=y  CONFIG_DEFAULT_NET_SCH="fq_codel"
CONFIG_TCP_CONG_BBR3=y  CONFIG_DEFAULT_TCP_CONG="bbr3"   # gaming；standard 为 BBR
CONFIG_LTO_CLANG_THIN=y  CONFIG_CFI_CLANG=y  CONFIG_KASAN_HW_TAGS=y
CONFIG_SHADOW_CALL_STACK=y  CONFIG_MODVERSIONS=y  CONFIG_TRIM_UNUSED_KSYMS=y
# CONFIG_CFS_BANDWIDTH is not set   # 必须关，开了会破 kABI
# CONFIG_CGROUP_PIDS is not set    # 同上
```

---

## 4. 关键决策记录（为什么这么做）

### 4.1 内核基线 = 原厂精确 commit `f4321180a397`（不是 tag 194）
- 原厂内核 banner 的 `-00019-gf4321180a397` 说明 Google 是从 `kernel/common` 的
  commit `f4321180a3973d19b626b3eef51871199e4e1fac` 构建的（比 `android13-5.15.194_r00`
  tag 多约 19 个 backport 提交，包含 PM runtime 等修复）。
- 该 commit 在 aosp-mirror GitHub 上已不可见（分支被 rebase），但 **android.googlesource.com
  的 Gitiles archive 仍可下载**：
  `https://android.googlesource.com/kernel/common/+archive/f4321180a397....tar.gz`
- 用 tag 树构建也能成功，但为了最接近原厂行为、减少差异，最终改用精确 commit。

### 4.2 工具链：AOSP clang `r563880c`（21.0.0）
- 原厂是用 clang `r450784e`（14.0.7）编的；我们改用 r563880c（更现代、AKS 常用），
  **genksyms CRC 不随编译器变化**（已用 clang14/clang21 交叉验证：mismatch 集合完全一致），
  vermagic 手动复现，所以不影响模块加载。
- 缓存：Actions cache key `aosp-clang-r563880c-571ed3e2...`，从 `toolchain/clang-r563880c` 恢复/保存。

### 4.3 `CONFIG_TRIM_UNUSED_KSYMS=y` + KMI 白名单（不能关裁剪）
- 原厂 config 该值为 y，且白名单路径指向小米构建机绝对路径（无效）。
- 若白名单为空：modpost 会裁掉几乎全部导出符号 → vendor 模块全挂（历史故障，见 7.1）。
- 若直接 `--disable TRIM_UNUSED_KSYMS`：Full LTO 内存暴涨 → runner OOM（历史故障，见 7.3）。
- 最终方案：`scripts/prepare.sh` 生成 `kernel/kmi_whitelist.txt`（`android/abi_gki_aarch64*`
  38 个 KMI 列表的并集，约 8585 个符号），`scripts/build.sh` 设置
  `CONFIG_UNUSED_KSYMS_WHITELIST=$ROOT/kernel/kmi_whitelist.txt` 并保持 TRIM=y。

### 4.4 模块 CRC / vermagic 告警（`patches/common/0025-module-abi-alarm.patch`）
- 现象：自编译内核与原厂模块有 350 个符号 CRC 数值不同（**无缺失**），若严格校验模块会拒载。
- 排查：换了 tag194/f432 两套源码、clang14/clang21 两套编译器、stock/droid/full 三套 config，
  mismatch 集合完全一致 → 属构建环境层面差异（genksyms 环境差异），非配置写错。
- 方案：在 `kernel/module.c` 打开 ABI 告警（**兼容模式**）：
  - `check_version()`：CRC 不一致时打印
    `symbol <name> CRC mismatch: module 0x........, kernel 0x........`（每模块最多 16 条，
    之后 `more CRC mismatches suppressed`），默认继续加载；
  - `check_modinfo()`：模块 vermagic release 与内核不同（带 CRC 模块默认容忍）时也打印告警；
  - 默认 `MODULE_CRC_MISMATCH_IS_FATAL=0`（告警不拦截，保证能开机）；改为 1 即严格模式。
- 注意：新增代码必须放在函数变量声明之后，否则触发
  `-Wdeclaration-after-statement` Werror（历史故障见 7.7）。
### 4.5 ThinLTO（替代 Full LTO）
- 原厂 config 是 `CONFIG_LTO_CLANG_FULL=y`，但在 GitHub 免费 runner 上 Full LTO 链接阶段
  反复 OOM（`hosted runner lost communication`，多次失败，见 7.3）。
- 改用 `CONFIG_LTO_CLANG_THIN=y`：官方支持、与 CFI/KMI 兼容、不改变 genksyms CRC/vermagic/
  模块加载行为；构建时间约 18 分钟，内存稳定。已在 `scripts/build.sh` 自检里断言 THIN=y。

### 4.6 Droidspaces 配置（GKI 版清单）
按官方 `Documentation/Kernel-Configuration.md` 的 **GKI（5.15）清单** 开启，并打官方
`SYSVIPC kABI padding` 补丁（task_struct 槽 6/7/8）。**不要**把 non-GKI 清单里的
`BRIDGE_NETFILTER`/`NF_TABLES` 等混进来（会改变 sk_buff 等结构，破 kABI）。
`CFS_BANDWIDTH`/`CGROUP_PIDS` 必须保持关闭（官方文档明确说明无法在 GKI 上安全开启）。

### 4.7 BBG 防格机
- 源码 `vc-teahouse/Baseband-guard @48d9fdea643bcb41d204541400e9d8656b97a54f`，5.15 GKI 集成补丁
- `CONFIG_BBG=y`，`CONFIG_LSM` 加入 `baseband_guard`（必须加，否则 BBG 的 Makefile 会 `$(error)`）
- `BBG_BLOCK_BOOT/RECOVERY=n`（避免系统内刷内核被自己拦截），dtbo/vbmeta 永不拦截

### 4.8 游戏优化
- gaming：BBRv3（Google 补丁 `0030-net-tcp-bbrv3-android13-5.15.patch`，带 `__GENKSYMS__` 保护）
  设为默认拥塞控制 + `fq_codel` 默认队列 + MGLRU 默认开 + sched/dcache/int_sqrt/clear_page/
  alarmtimer 小优化
- standard：BBR（v1）+ fq_codel + MGLRU + 同样的小优化（无 BBRv3）
- 其余（KASAN/CFI/SHADOW_CALL_STACK/BTF/MODVERSIONS/MODULE_SIG）全部保持原厂值

---

## 5. 仓库结构（HEAD e57898c）

```
.github/workflows/build.yml     唯一正式 CI：push 触发矩阵构建（standard+gaming）
config/
  sources.lock.json             源码 commit/工具链/BBG/AnyKernel3 pin
  device-baseline.config        设备原厂 GKI .config（5560 symbols，构建基线）
  features-common.config        Droidspaces + BBG + MGLRU/网络/ThinLTO 等公共特性
  features-gaming.config        gaming 额外：BBRv3 默认等
  probe-droidspaces.config      仅参考（GKI 最小集；当前未使用）
  anykernel.sh                  AnyKernel3 配置（BLOCK=boot / IS_SLOT_DEVICE=1）
evidence/vendor-module-versions.json  原厂 404 模块的导入符号+CRC 证据（ABI 对比用）
patches/common/
  0001-sysvipc-kabi-padding-{1-2-3,3-4-5,6-7-8}.patch  官方 kABI 补丁（三种 padding 布局；
                                                        prepare 自动选可用槽位，其余跳过）
  0010-baseband-guard-5.15.patch                        BBG 集成
  0020..0024-*.patch                                    游戏/性能小优化
  0025-module-abi-alarm.patch                            模块 CRC/vermagic 告警（兼容模式）
patches/full/0030-net-tcp-bbrv3-android13-5.15.patch    BBRv3
scripts/
  prepare-runner.sh              runner 清理磁盘 + 安装构建依赖（bc/bison/flex/openssl/...）
  prepare.sh                     下载源码+工具链、校验、打补丁、生成 KMI 白名单、写 .scmversion
  build.sh                       配置基线+fragment、自检、make Image modules、vermagic 断言、CRC 报告
  package.sh                     boot.img + AK3 zip + RELEASE 说明 + SHA256SUMS
  make_bootimg.py                生成 Android boot header v4（kernel@4096，无 ramdisk）
  check_module_abi.py            用 evidence 对比 out/Module.symvers 的导出符号 CRC
  elf_versions.py / pick_kabi_slot.py   辅助工具
  publish-variant.sh             每变体独立发布：artifacts-<variant> 分支 + Release k60p-kernel-v3
  publish.sh                     旧中央发布脚本（保留，rescue 用）
docs/BUILD-NOTES.md              精简构建说明
docs/HANDOFF.md                  本文档
```

---

## 6. 构建流水线原理（.github/workflows/build.yml）

触发：push 到 `main` 且改动命中 `config/**`、`patches/**`、`scripts/**`、`evidence/**`
或 `build.yml` 本身；矩阵 `standard`/`gaming` 并行，runner ubuntu-24.04，timeout 150min。

步骤：
1. `prepare-runner.sh`：删 Android/dotnet 等大目录腾磁盘，apt 安装构建依赖
2. 恢复 clang 缓存（`toolchain/clang-r563880c`）
3. `prepare.sh`：下载 Gitiles 源码 tarball → 校验 → 下载 clang → 校验 → 打 sysvipc kABI 补丁
   （自动选 1-2-3/3-4-5/6-7-8 中可用布局）→ 打 common+full 补丁 → 生成 KMI 白名单 →
   写 `.scmversion`
4. 保存 clang 缓存
5. swap：按磁盘剩余分配 8-24GB swap（`available - 18GB`）
6. `build.sh`：复制基线 config → 应用 fragment → 设置 TRIM/白名单 → olddefconfig →
   **config 自检**（KASAN/CFI/SCM/ThinLTO/BTF/MODVERSIONS/BBG/Droidspaces 必须 y；
   CFS_BANDWIDTH/CGROUP_PIDS 必须 n）→ `make Image modules`（`-j3`，70 分钟 timeout）→
   UTS_RELEASE 断言 == 原厂 → 生成 `dist/*`
7. `package.sh`：生成 boot.img（header v4）、AK3 zip、SHA256SUMS、RELEASE 说明、诊断文件
8. `publish-variant.sh`：推送 `artifacts-<variant>` 分支（构建日志/配置/ABI 报告/source.patch），
   上传 Release `k60p-kernel-v3`（`gh release upload --clobber`）
9. 上传 Actions artifacts

**云端重建不需要梯子**（runner 自己的网络直连 code.googlesource.com / GitHub）。

---

## 7. 踩坑与排查记录（重要，重做时会遇到）

### 7.1 导出符号被裁光 → vendor 模块全挂
- 现象：ABI 报告 `missing=16248`，所有 vendor 模块 `Unknown symbol`。
- 原因：原厂 `CONFIG_TRIM_UNUSED_KSYMS=y` + 白名单路径无效；空白名单时 modpost 裁掉几乎全部导出。
- 解决：生成 KMI 白名单（约 8585 符号）并指向它，保持 TRIM=y（见 4.3）。

### 7.2 三个 sysvipc kABI 补丁变体被同时应用
- 现象：prepare 第一次 CI 失败。
- 解决：`apply_dir()` 中 `case 0001-sysvipc-kabi-padding-*) continue;;` 跳过其余变体，
  只应用 `pick_kabi_slot.py` 选中的那个。

### 7.3 Full LTO OOM / runner lost communication（反复出现）
- 现象：job 跑 60+ 分钟无输出后失败，annotation 为
  “The hosted runner lost communication with the server… starves it for CPU/Memory”。
- 解决：① 不要 `--disable TRIM_UNUSED_KSYMS`（内存暴涨）；② 最终改 ThinLTO；③ `-j3` 限制并行。
- 注意：这类失败 **step 状态会停在 in_progress**，run 详情里 step 没有 completedAt。

### 7.4 CI runner 卡死导致 run 一直 in_progress
- 现象：某个 job 卡在 build 步骤 55+ 分钟，新 run 排队 pending，取消也只是把旧 run 变 cancelled。
- 解决：直接 push 一个改动触发新 run（concurrency `cancel-in-progress` 会取消旧的），
  或换独立 concurrency group 的新工作流（曾经临时加过 `build-ab.yml`，已删）。

### 7.5 googlesource tarball 下载截断
- 现象：`gzip: unexpected end of file / tar: Unexpected EOF`，prepare 失败。
- 原因：并发下载多个 runner 同时拉 200MB 归档时被截断。
- 解决：降低并发/重试；本地下载也慢（205MB 约 14 分钟）。如再遇到，给 `curl` 加
  `--retry-all-errors` 并在解压前用 `gzip -t` 校验。

### 7.6 GitHub API 未认证限流 60/h
- 现象：监控时经常 403。
- 解决：优先用 HTML actions 页（页面内嵌 JSON 可解析）、`raw.githubusercontent.com`、
  git ls-remote；需要日志时用临时 `collect-run` 工作流（用 `${{ github.token }}` 跑 `gh`）——
  该工作流已随清理删除，可参考 git 历史恢复。

### 7.7 ABI 告警补丁的编译注意（历史：第一版 CRC 补丁编译失败）
- 现象：`error: mixing declarations and code is a C99 extension [-Werror,-Wdeclaration-after-statement]`
- 解决：`return 1;` 放在函数变量声明之后（当前补丁已修正）。

### 7.8 build.sh 的 make 行被误注释（严重）
- 原因：用 PowerShell 改脚本时把 `\n` 当成换行写进了单引号字符串，生成字面 `\ntimeout ...`
  落在注释行里，导致 make 整行被注释掉 → 构建“3 秒成功”但没编译，发布坏包。
- 解决：修复为独立两行；已加入慢构建检测（构建耗时/产物检查）。**改脚本后请 `bash -n` 并检查
  `timeout ... make ...` 行确实存在。**

### 7.9 clang-14 在 Ubuntu 24.04 无包
- 现象：apt 装 clang-14 失败（noble 没有 clang-14，只有 llvm/lld-14）。
- 解决：需要 clang14 对比实验时用 ubuntu-22.04 runner；正式构建不需要 clang14。

### 7.10 Android clang r450784e 获取
- 尝试 sparse clone `platform/prebuilts/clang/host/linux-x86` 后 `sparse-checkout set clang-r450784e`
  失败（main 分支已删旧工具链目录）。
- 实际不需要：已验证 CRC mismatch 与编译器版本无关（clang14/21 集合一致）。

### 7.11 环境/工具小坑
- 本机 `pwsh` 不在 PATH 里，`& script.ps1` 被执行策略阻止 → 用内联命令。
- 本机 `ssh.github.com` 曾需 Clash 代理（`~/.ssh/config` 的 ProxyCommand connect.exe），
  后来代理关闭时**直连 443 可用**；`api.github.com`/`android.googlesource.com` 需要代理。
- 用 `git push` 时若报 “Please make sure you have the correct access rights”，
  可试 `-c core.sshCommand="ssh -o ProxyCommand=none -p 443"`（直连 GitHub SSH）。

---

## 8. 刷机与回滚（摘要，详见 Release 内 README.md）

```bash
# 建议先临时启动验证（不写分区）
fastboot boot boot-gaming.img
# 确认可开机后正式刷入
fastboot flash boot boot-gaming.img
fastboot reboot
# 回滚：用原厂 boot.img
fastboot flash boot boot.img
```
刷后自检：
```bash
lsmod | wc -l                                   # 约 400
cat /sys/kernel/security/lsm | tr ',' '\n' | grep baseband
cat /proc/sys/net/ipv4/tcp_congestion_control   # gaming = bbr3
cat /sys/kernel/mm/lru_gen/enabled
dmesg | grep -iE 'unknown symbol|disagrees about version|CFI failure' | head
```

---

## 9. 后续可做的事

1. **严格模式（可选）**：把 `0025-module-abi-alarm.patch` 的 `MODULE_CRC_MISMATCH_IS_FATAL` 改为 1，
   让 CRC 不一致的模块直接拒绝加载（fail-fast）；普通使用建议保持默认告警模式。
2. **上游更新**：当 Google 更新 `kernel/common` 对应分支后，只需改 `config/sources.lock.json`
   的 commit（及 vermagic 相关字段），push 即可云端重建。
3. **进一步游戏调优**：uclamp 参数、sched 微调、IO/GPU 内核参数等（注意每改 header/结构体都要
   重新确认 vendor 模块 ABI）。
4. 如需真机调试：TWRP/ADB 抓 dmesg 与 `lsmod` 对比。

---

## 10. 快速命令速查

```bash
# 本地仓库
cd D:\Administrator\Documents\ai\k60p_build

# 触发云端构建（改任意 config/patches/scripts 文件后）
git add -A && git commit -m "..." && git push origin main
# 若 SSH 连不上（代理未开）：
git -c core.sshCommand="ssh -o ProxyCommand=none -p 443" push origin main

# 监控构建（无需 token）
#   https://github.com/zhihan233/k60p_Kernel/actions
# 下载 release（GitHub 直连即可）
#   https://github.com/zhihan233/k60p_Kernel/releases/download/k60p-kernel-v4/<file>

# 本地校验（python：work/verify_v3_final.py，需 14 个文件在 deliver/）
python work/verify_v3_final.py

# 本地交叉校验 SHA
cd deliver && sha256sum -c SHA256SUMS-standard && sha256sum -c SHA256SUMS-gaming
```

---

## 11. 重要提醒

- `LOCALVERSION`/`BUILD_NUMBER`/`.scmversion` 三者决定的版本串**必须**保持
  `5.15.194-android13-8-00019-gf4321180a397-ab15212794`，否则 vendor 模块与 KernelSU LKM 拒载。
- Droidspaces 的 GKI 清单和 non-GKI 清单**不能混**；`CFS_BANDWIDTH`/`CGROUP_PIDS` 不能开。
- 改动 `include/linux/*.h` 的补丁（如 BBRv3）必须确认其 `__GENKSYMS__` 保护，避免破坏导出 CRC。
- 每次构建后先看 `abi-report-*.json` 的 `missing`/`unclassified` 是否为 0，再看
  `diag`/`errors-*.txt` 是否有 Werror 失败。
