#!/usr/bin/env bash
# 「最新 5.15」变体编译：设备原厂配置 + 容器/BBG/游戏特性，natural release 5.15.226-android13-8。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p dist out

TOOLCHAIN_DIR="clang-r563880c"
export PATH="$ROOT/toolchain/$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64 LLVM=1 LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KBUILD_BUILD_USER=socrates KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_VERSION=1
export LOCALVERSION="-android13-8"
JOBS="${JOBS:-$(nproc)}"
VARIANT="latest"

echo "== clang: $(clang --version | head -1)"
echo "== jobs: $JOBS"

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
      \"*\" )
        val="${val#\"}"; val="${val%\"}"
        kernel/scripts/config --file out/.config --set-str "$sym" "$val" ;;
      *) kernel/scripts/config --file out/.config --set-val "$sym" "$val" ;;
    esac
  done < "$1"
}
apply_cfg config/features-common.config
apply_cfg config/features-gaming.config
kernel/scripts/config --file out/.config --disable UNUSED_KSYMS_WHITELIST

make -C kernel O="$ROOT/out" olddefconfig
kernel/scripts/diffconfig config/device-baseline.config out/.config > "dist/config-${VARIANT}.diff" || true
cp out/.config "dist/kernel-${VARIANT}.config"

python3 - <<'PY'
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
for name in ('CONFIG_MODVERSIONS', 'CONFIG_CFI_CLANG', 'CONFIG_KASAN', 'CONFIG_KASAN_HW_TAGS',
             'CONFIG_SHADOW_CALL_STACK', 'CONFIG_DEBUG_INFO_BTF', 'CONFIG_MODULE_SIG_PROTECT',
             'CONFIG_MODULE_SIG', 'CONFIG_LTO_CLANG', 'CONFIG_ARM64_MTE'):
    assert actual.get(name) == 'y', (name, actual.get(name))
for name in ('CONFIG_CFS_BANDWIDTH', 'CONFIG_CGROUP_PIDS'):
    assert actual.get(name, 'n') == 'n', (name, actual.get(name))
for name in ('CONFIG_PID_NS', 'CONFIG_IPC_NS', 'CONFIG_SYSVIPC', 'CONFIG_DEVTMPFS',
             'CONFIG_USER_NS', 'CONFIG_POSIX_MQUEUE', 'CONFIG_NETFILTER_XT_MATCH_ADDRTYPE',
             'CONFIG_MACVLAN', 'CONFIG_IP6_NF_NAT', 'CONFIG_IP6_NF_TARGET_MASQUERADE'):
    assert actual.get(name) == 'y', (name, actual.get(name))
assert actual.get('CONFIG_BBG') == 'y'
assert 'baseband_guard' in actual.get('CONFIG_LSM', '')
assert actual.get('CONFIG_LRU_GEN_ENABLED') == 'y'
assert actual.get('CONFIG_TCP_CONG_BBR3') == 'y'
assert actual.get('CONFIG_DEFAULT_TCP_CONG') == '"bbr3"'
print("== config self-check passed")
PY

echo "== build"
set +e
make -C kernel O="$ROOT/out" -j"$JOBS" Image modules 2>&1 | tee dist/build-latest.log
rc=${PIPESTATUS[0]}
set -e
if [[ "$rc" != 0 ]]; then
  echo "!! kernel build failed rc=$rc"
  mkdir -p dist/ci-artifacts
  {
    echo "=== error lines ==="
    grep -n -i -E 'error:|fatal error|undefined reference|No rule to make' dist/build-latest.log | head -n 300 || true
    echo
    echo "=== tail 400 ==="
    tail -n 400 dist/build-latest.log || true
  } > dist/ci-artifacts/errors-latest.txt
  echo "BUILD_FAILED" > dist/ci-artifacts/status-latest.txt
  exit 1
fi

cp out/arch/arm64/boot/Image "dist/Image-${VARIANT}"
cp out/Module.symvers "dist/Module.symvers-${VARIANT}"
cp out/include/generated/utsrelease.h "dist/utsrelease-${VARIANT}.h"
cp out/.config "dist/kernel-${VARIANT}.config"

echo "== vermagic check (expected 5.15.226-android13-8)"
python3 - <<'PY'
from pathlib import Path
built = Path('dist/utsrelease-latest.h').read_text().split('"')[1]
print("built UTS_RELEASE:", built)
assert built.startswith('5.15.226'), built
Path('dist/release-latest.txt').write_text(built + '\n')
PY

echo "== vendor module CRC check"
set +e
python3 scripts/check_module_abi.py "dist/Module.symvers-${VARIANT}" \
  evidence/vendor-module-versions.json --report "dist/abi-report-${VARIANT}.json"
crc_rc=$?
set -e
[[ "$crc_rc" == 0 ]] && echo "== CRC check passed" || echo "!! CRC mismatch (see report)"

python3 - <<PY
import hashlib, json, os
from pathlib import Path
release = Path('dist/release-latest.txt').read_text().strip()
lock = json.load(open('config/sources.lock.json'))
info = {
    'device': lock['device'], 'device_name': lock['device_name'], 'rom': lock['rom'],
    'variant': 'latest',
    'source': 'ACK android13-5.15-lts (5.15.195) merged with upstream stable 5.15.226 (-X ours)',
    'kernel_release': release,
    'modules_compatible': 'vermagic 放宽补丁已应用：无 __versions 的模块（KernelSU/SukiSU LKM）也可加载',
    'ci_run_id': os.environ.get('GITHUB_RUN_ID'),
    'features': ['Droidspaces + kABI padding', 'BBG', 'BBRv3 default + fq_codel + MGLRU'],
    'vendor_module_crc_check': 'PASS' if $crc_rc == 0 else 'FAIL',
    'hashes': {n: hashlib.sha256((Path('dist') / n).read_bytes()).hexdigest()
               for n in ('Image-${VARIANT}', 'kernel-${VARIANT}.config')
               if (Path('dist') / n).exists()},
}
Path('dist/build-${VARIANT}.json').write_text(json.dumps(info, indent=2) + '\n')
status = 'OK' if $crc_rc == 0 else 'ABI_MISMATCH'
Path('dist/status-${VARIANT}.txt').write_text(f"variant=latest\nrelease={release}\nbuild=OK\nabi={status}\n")
PY

df -h .
ls -la dist/
