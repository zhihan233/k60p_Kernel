#!/usr/bin/env bash
# 应用设备原厂配置 + 功能 fragment，编译 Image/modules，并做 vendor 模块 CRC 校验。
# 环境变量: VARIANT=standard|gaming
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VARIANT="${VARIANT:-standard}"
mkdir -p dist out

readarray -t META < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))
k, t = x['kernel'], x['toolchain']
for v in (k['release'], k['localversion'], k['build_number'], t['directory']):
    print(v)
PY
)
RELEASE="${META[0]}"; LOCALVER="${META[1]}"; BUILD_NUM="${META[2]}"; TOOLCHAIN_DIR="${META[3]}"

export PATH="$ROOT/toolchain/$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64 LLVM=1 LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KBUILD_BUILD_USER=socrates KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_VERSION=1
export LOCALVERSION="$LOCALVER"
export BUILD_NUMBER="$BUILD_NUM"
JOBS="${JOBS:-$(( $(nproc) < 3 ? $(nproc) : 3 ))}"

echo "== clang: $(clang --version | head -1)"
echo "== variant: ${VARIANT}, jobs: ${JOBS}"

collect_diagnostics() {
  mkdir -p dist/ci-artifacts
  if [[ -f dist/build.log ]]; then
    {
      echo "=== error lines ==="
      grep -n -i -E 'error:|Error [0-9]+|fatal error|undefined reference|No rule to make|recipe for target|Killed' dist/build.log | head -n 300 || true
      echo
      echo "=== tail 400 ==="
      tail -n 400 dist/build.log || true
    } > "dist/ci-artifacts/errors-${VARIANT}.txt"
    gzip -9 -c dist/build.log > "dist/ci-artifacts/build-${VARIANT}.log.gz" || true
  fi
  if [[ -f out/.config ]]; then
    cp out/.config "dist/ci-artifacts/kernel-${VARIANT}.config" || true
  fi
  echo "BUILD_FAILED" > "dist/ci-artifacts/status-${VARIANT}.txt"
}

# ---------------- 1. 配置 ----------------
cp config/device-baseline.config out/.config

apply_cfg() {
  local line sym val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
      '') continue ;;
      '#'*)
        if [[ "$line" == "# CONFIG_"*" is not set" ]]; then
          sym="${line#\# CONFIG_}"; sym="${sym%% is not set*}"
          kernel/scripts/config --file out/.config --disable "$sym"
        fi
        continue ;;
    esac
    [[ "$line" == CONFIG_*=* ]] || continue
    sym="${line%%=*}"; val="${line#*=}"
    case "$val" in
      y) kernel/scripts/config --file out/.config --enable "$sym" ;;
      n) kernel/scripts/config --file out/.config --disable "$sym" ;;
      \"*\")
        val="${val#\"}"; val="${val%\"}"
        kernel/scripts/config --file out/.config --set-str "$sym" "$val" ;;
      *) kernel/scripts/config --file out/.config --set-val "$sym" "$val" ;;
    esac
  done < "$1"
}

apply_cfg config/features-common.config
if [[ "${VARIANT}" == "gaming" ]]; then
  apply_cfg config/features-gaming.config
fi
# 原厂配置 CONFIG_TRIM_UNUSED_KSYMS=y，但白名单指向小米构建机的绝对路径。
# 这里改成指向 prepare.sh 生成的 KMI 白名单（ACK android/abi_gki_aarch64* 全量符号），
# 既保持与原厂/Google GKI 构建一致的符号裁剪方式，又保证 400 个原厂 vendor 模块
# 需要的导出符号全部保留（否则会因 "Unknown symbol" 加载失败 → bootloop）。
WHITELIST="$ROOT/kernel/kmi_whitelist.txt"
if [[ ! -s "$WHITELIST" ]]; then
  echo "!! KMI whitelist missing: $WHITELIST"
  exit 1
fi
kernel/scripts/config --file out/.config --enable TRIM_UNUSED_KSYMS
kernel/scripts/config --file out/.config --set-str UNUSED_KSYMS_WHITELIST "$WHITELIST"

make -C kernel O="$ROOT/out" olddefconfig

kernel/scripts/diffconfig config/device-baseline.config out/.config > "dist/config-${VARIANT}.diff" || true
cp out/.config "dist/kernel-${VARIANT}.config"

# ---------------- 2. 配置自检 ----------------
python3 - "$VARIANT" <<'PY'
import sys
from pathlib import Path

def read(path):
    d = {}
    for line in Path(path).read_text(errors='replace').splitlines():
        line = line.strip()
        if line.startswith('# CONFIG_') and line.endswith(' is not set'):
            d[line[2:-len(' is not set')].strip()] = 'n'
        elif line.startswith('CONFIG_') and '=' in line:
            k, v = line.split('=', 1)
            d[k] = v
    return d

actual = read('out/.config')
baseline = read('config/device-baseline.config')
variant = sys.argv[1]

# 原厂启动硬约束（改了就 bootloop：KASAN/CFI/SHADOW_CALL_STACK/LTO/BTF/MODVERSIONS）
for name in ('CONFIG_MODVERSIONS', 'CONFIG_CFI_CLANG', 'CONFIG_LTO_CLANG_FULL',
             'CONFIG_KASAN_HW_TAGS', 'CONFIG_SHADOW_CALL_STACK', 'CONFIG_DEBUG_INFO_BTF',
             'CONFIG_MODULE_SIG_PROTECT', 'CONFIG_MODULE_SIG'):
    assert actual.get(name) == baseline.get(name) == 'y', (name, actual.get(name), baseline.get(name))
# 会破坏 kABI 的两项保持原厂关闭
for name in ('CONFIG_CFS_BANDWIDTH', 'CONFIG_CGROUP_PIDS'):
    assert actual.get(name) == baseline.get(name), (name, actual.get(name), baseline.get(name))
# Droidspaces 必需项
for name in ('CONFIG_PID_NS', 'CONFIG_IPC_NS', 'CONFIG_SYSVIPC', 'CONFIG_DEVTMPFS',
             'CONFIG_USER_NS', 'CONFIG_POSIX_MQUEUE', 'CONFIG_NETFILTER_XT_MATCH_ADDRTYPE',
             'CONFIG_MACVLAN', 'CONFIG_IP6_NF_NAT', 'CONFIG_IP6_NF_TARGET_MASQUERADE'):
    assert actual.get(name) == 'y', (name, actual.get(name))
# BBG
assert actual.get('CONFIG_BBG') == 'y', actual.get('CONFIG_BBG')
assert 'baseband_guard' in actual.get('CONFIG_LSM', ''), actual.get('CONFIG_LSM')
# 构建修正：保持原厂 TRIM=y，白名单指向生成的 KMI 符号表
assert actual.get('CONFIG_TRIM_UNUSED_KSYMS') == 'y', actual.get('CONFIG_TRIM_UNUSED_KSYMS')
assert 'kmi_whitelist.txt' in actual.get('CONFIG_UNUSED_KSYMS_WHITELIST', ''), actual.get('CONFIG_UNUSED_KSYMS_WHITELIST')
# 游戏优化
assert actual.get('CONFIG_LRU_GEN_ENABLED') == 'y'
assert actual.get('CONFIG_DEFAULT_FQ_CODEL') == 'y'
assert actual.get('CONFIG_TCP_CONG_BBR') == 'y'
if variant == 'gaming':
    assert actual.get('CONFIG_TCP_CONG_BBR3') == 'y', actual.get('CONFIG_TCP_CONG_BBR3')
    assert actual.get('CONFIG_DEFAULT_TCP_CONG') == '"bbr3"', actual.get('CONFIG_DEFAULT_TCP_CONG')
print("== config self-check passed")
PY

# ---------------- 3. 编译 ----------------
set +e
# timeout 防止个别 runner 卡死无限占用（正常构建 15-25 分钟）\ntimeout --signal=KILL 4200 make -C kernel O="$ROOT/out" -j"$JOBS" Image modules 2>&1 | tee dist/build.log
rc=${PIPESTATUS[0]}
set -e
if [[ "$rc" != 0 ]]; then
  echo "!! kernel build failed (rc=$rc)"
  collect_diagnostics
  exit 1
fi

cp out/arch/arm64/boot/Image "dist/Image-${VARIANT}"
cp out/Module.symvers "dist/Module.symvers-${VARIANT}"
cp out/include/generated/utsrelease.h "dist/utsrelease-${VARIANT}.h"
cp out/.config "dist/kernel-${VARIANT}.config"

# ---------------- 4. vermagic 必须与原厂完全一致 ----------------
python3 - "${RELEASE}" "${VARIANT}" <<'PY'
import json, sys
from pathlib import Path
release, variant = sys.argv[1], sys.argv[2]
built = Path(f'dist/utsrelease-{variant}.h').read_text().split('"')[1]
print(f"== built UTS_RELEASE : {built}")
print(f"== device release    : {release}")
assert built == release, (built, release)
PY

# ---------------- 5. 原厂 vendor 模块 CRC 对比 ----------------
echo "== comparing module symbol CRCs against device vendor-module inventory"
set +e
python3 scripts/check_module_abi.py "dist/Module.symvers-${VARIANT}" \
  evidence/vendor-module-versions.json --report "dist/abi-report-${VARIANT}.json"
crc_rc=$?
set -e
if [[ "$crc_rc" != 0 ]]; then
  echo "!! WARNING: vendor module CRC mismatch detected (see dist/abi-report-${VARIANT}.json)"
else
  echo "== vendor module CRC check passed"
fi

# ---------------- 6. build.json + status ----------------
python3 - "${VARIANT}" "${crc_rc}" <<'PY'
import hashlib, json, os, subprocess, sys
from pathlib import Path
variant, crc_rc = sys.argv[1], int(sys.argv[2])
lock = json.load(open('config/sources.lock.json'))
release = Path(f'dist/utsrelease-{variant}.h').read_text().split('"')[1]
sha = {}
for name in (f'Image-{variant}', f'kernel-{variant}.config'):
    p = Path('dist') / name
    if p.exists():
        sha[name] = hashlib.sha256(p.read_bytes()).hexdigest()
info = {
    'device': lock['device'], 'device_name': lock['device_name'], 'rom': lock['rom'],
    'variant': variant,
    'kernel': lock['kernel'],
    'toolchain': {'version': lock['toolchain']['version'], 'directory': lock['toolchain']['directory']},
    'kernel_release': release,
    'ci_run_id': os.environ.get('GITHUB_RUN_ID'),
    'ci_commit': os.environ.get('GITHUB_SHA'),
    'features': {
        'droidspaces': 'SYSVIPC/POSIX_MQUEUE/IPC_NS/PID_NS/USER_NS/DEVTMPFS/NAT/MACVLAN + kABI padding',
        'bbg': 'Baseband-guard 防格机 LSM (boot/recovery 保护关闭)',
        'gaming': 'BBRv3 + fq_codel + MGLRU default + sched/io tweaks' if variant == 'gaming' else 'BBR/fq_codel + MGLRU default',
    },
    'vendor_module_crc_check': 'PASS' if crc_rc == 0 else 'FAIL',
    'hashes': sha,
    'validation': 'Built Image + vendored module imported-symbol CRC comparison; device boot not tested in CI',
}
Path(f'dist/build-{variant}.json').write_text(json.dumps(info, indent=2) + '\n')
status = 'OK' if crc_rc == 0 else 'ABI_MISMATCH'
Path(f'dist/status-{variant}.txt').write_text(
    f"variant={variant}\nrelease={release}\nbuild=OK\nabi={status}\n")
print("== build summary written")
PY

df -h .
ls -la dist/
