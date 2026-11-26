#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# 用设备基线 config + Droidspaces/BBG/游戏配置构建 LineageOS 内核，并对比厂商模块 CRC。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VARIANT="${VARIANT:-los}"
TOOLCHAIN_DIR=$(python3 -c "import json; print(json.load(open('config/sources.lock.json'))['toolchain']['directory'])")
RELEASE=$(python3 -c "import json; print(json.load(open('config/sources.lock.json'))['kernel']['release'])")

export PATH="$ROOT/toolchain/$TOOLCHAIN_DIR/bin:$PATH"
export ARCH=arm64 LLVM=1 LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KBUILD_BUILD_USER=socrates KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_TIMESTAMP='Sat Sep 19 06:31:47 UTC 2026'
export KBUILD_BUILD_VERSION=1
JOBS="${JOBS:-$(nproc)}"
mkdir -p out dist

echo "== variant: ${VARIANT}, jobs: ${JOBS}, toolchain: ${TOOLCHAIN_DIR}"
clang --version | head -2

collect_diagnostics() {
  mkdir -p dist/ci-artifacts
  if [[ -f dist/build.log ]]; then
    {
      echo "=== error lines ==="
      grep -n -i -E 'error:|Error [0-9]+|fatal error|undefined reference|No rule to make|recipe for target|Killed' dist/build.log | head -n 300 || true
      echo
      echo "=== tail 300 ==="
      tail -n 300 dist/build.log || true
    } > "dist/ci-artifacts/errors-${VARIANT}.txt"
    gzip -9 -c dist/build.log > "dist/ci-artifacts/build-${VARIANT}.log.gz" || true
  fi
  [[ -f out/.config ]] && cp out/.config "dist/ci-artifacts/kernel-${VARIANT}.config" || true
  echo "BUILD_FAILED" > "dist/ci-artifacts/status-${VARIANT}.txt"
}

# ---------- 1. config ----------
cp config/device-baseline.config out/.config

# ThinLTO：Full LTO 在 GitHub runner 上反复内存不足（run 45755782891 第 68 分钟 runner 失联）。
# ThinLTO 与 Full LTO 生成代码等价，genksyms CRC / CFI 类型哈希 / vermagic 均不受影响。
echo "== switching LTO to Thin"
for cfg in kernel/arch/arm64/configs/gki_defconfig out/.config; do
  kernel/scripts/config --file "$cfg" --enable LTO_CLANG_THIN
  kernel/scripts/config --file "$cfg" --disable LTO_CLANG_FULL
done

enable_cfg() { # $1=name, applies to both gki_defconfig and out/.config
  local name="$1"
  kernel/scripts/config --file kernel/arch/arm64/configs/gki_defconfig --enable "$name"
  kernel/scripts/config --file out/.config --enable "$name"
}

echo "== applying Droidspaces config"
while IFS= read -r entry; do
  [[ "$entry" =~ ^CONFIG_([A-Z0-9_]+)=y$ ]] || continue
  enable_cfg "${BASH_REMATCH[1]}"
done < config/droidspaces.config

echo "== applying extras config (best effort)"
while IFS= read -r entry; do
  [[ "$entry" =~ ^CONFIG_([A-Z0-9_]+)=y$ ]] || continue
  enable_cfg "${BASH_REMATCH[1]}"
done < config/extras.config

# BBG: 生成 LSM 字符串（插入 baseband_guard），写回两份 config
python3 - <<'PY'
from pathlib import Path
lsm = "landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,baseband_guard,smack,tomoyo,apparmor,bpf"
for path in (Path('kernel/arch/arm64/configs/gki_defconfig'), Path('out/.config')):
    lines = path.read_text().splitlines()
    out = []
    found = False
    for line in lines:
        if line.startswith('CONFIG_LSM='):
            out.append(f'CONFIG_LSM="{lsm}"')
            found = True
        else:
            out.append(line)
    if not found:
        out.append(f'CONFIG_LSM="{lsm}"')
    path.write_text("\n".join(out) + "\n")
print("== LSM (BBG) written:", lsm)
PY

make -C kernel O="$ROOT/out" olddefconfig
kernel/scripts/diffconfig config/device-baseline.config out/.config > "dist/config-${VARIANT}.diff" || true
cp out/.config "dist/kernel-${VARIANT}.config"

# ---------- 2. config self-check ----------
VARIANT="$VARIANT" python3 - <<'PY'
import os
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

for name in ('CONFIG_MODVERSIONS', 'CONFIG_CFI_CLANG', 'CONFIG_LTO', 'CONFIG_LTO_CLANG',
             'CONFIG_KASAN_HW_TAGS', 'CONFIG_SHADOW_CALL_STACK', 'CONFIG_DEBUG_INFO_BTF',
             'CONFIG_MODULE_SIG_PROTECT', 'CONFIG_TARGET_PRODUCT_SOCRATES'):
    assert actual.get(name) == baseline.get(name) == 'y', (name, actual.get(name), baseline.get(name))
# LTO 模式：CI 上用 ThinLTO（Full LTO 在 runner 上 OOM），ABI 等价
assert actual.get('CONFIG_LTO_CLANG_THIN') == 'y', actual.get('CONFIG_LTO_CLANG_THIN')
assert actual.get('CONFIG_LTO_CLANG_FULL') != 'y', actual.get('CONFIG_LTO_CLANG_FULL')
for name in ('CONFIG_CFS_BANDWIDTH', 'CONFIG_CGROUP_PIDS'):
    assert actual.get(name) == baseline.get(name), (name, actual.get(name), baseline.get(name))

wanted = read('config/droidspaces.config')
missing = [(n, actual.get(n), v) for n, v in wanted.items() if actual.get(n) != v]
assert not missing, f"Droidspaces config not enabled: {missing}"

assert actual.get('CONFIG_BBG') == 'y', actual.get('CONFIG_BBG')
assert 'baseband_guard' in actual.get('CONFIG_LSM', ''), actual.get('CONFIG_LSM')
assert actual.get('CONFIG_TRIM_UNUSED_KSYMS') != 'y', 'TRIM must stay off in this tree'

extras = read('config/extras.config')
missing_extras = [n for n in extras if actual.get(n) != 'y']
if missing_extras:
    print(f"== WARNING: extras not enabled (tree may not support): {missing_extras}")
print("== config self-check passed")
PY

# ---------- 3. build ----------
set +e
timeout --signal=KILL 6600 make -C kernel O="$ROOT/out" -j"$JOBS" Image modules 2>&1 | tee dist/build.log
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

# ---------- 4. vermagic ----------
python3 - "${RELEASE}" "${VARIANT}" <<'PY'
import sys
from pathlib import Path
release, variant = sys.argv[1], sys.argv[2]
built = Path(f'dist/utsrelease-{variant}.h').read_text().split('"')[1]
print(f"== built UTS_RELEASE : {built}")
print(f"== expected release  : {release}")
assert built == release, (built, release)
PY

# ---------- 5. vendor module ABI compare ----------
echo "== comparing vendor module symbol CRCs"
set +e
python3 scripts/check_module_abi.py "dist/Module.symvers-${VARIANT}" \
  evidence/vendor-module-versions.json --report "dist/abi-report-${VARIANT}.json"
crc_rc=$?
set -e
if [[ "$crc_rc" != 0 ]]; then
  echo "!! WARNING: vendor module CRC mismatch (see dist/abi-report-${VARIANT}.json)"
else
  echo "== vendor module CRC check passed (0 mismatch)"
fi

# ---------- 6. summary ----------
python3 - "${VARIANT}" "${crc_rc}" <<'PY'
import hashlib, json, os, sys
from pathlib import Path
variant, crc_rc = sys.argv[1], int(sys.argv[2])
lock = json.load(open('config/sources.lock.json'))
release = Path(f'dist/utsrelease-{variant}.h').read_text().split('"')[1]
a = json.load(open(f'dist/abi-report-{variant}.json'))
uniq = {m['symbol'] for m in a['crc_mismatches']}
missing = [m for m in a['crc_mismatches'] if m['built_crc'] == 'MISSING']
info = {
    'device': lock['device'], 'device_name': lock['device_name'], 'base': lock['base'],
    'rom_target': lock['rom_target'], 'variant': variant,
    'kernel': lock['kernel'], 'toolchain': lock['toolchain'],
    'kernel_release': release,
    'ci_run_id': os.environ.get('GITHUB_RUN_ID'),
    'ci_commit': os.environ.get('GITHUB_SHA'),
    'features': {
        'droidspaces': 'GKI 5.15 官方配置 + SYSVIPC kABI padding 6/7/8',
        'bbg': 'Baseband-guard LSM（boot/recovery 不拦截）',
        'game': 'MGLRU 默认开启 + fq_codel 默认队列 + BBR/ECN + 调度/内存小补丁',
        'lto': 'ThinLTO（CI 稳定性；与 Full LTO 生成代码等价，不影响 ABI/CRC/vermagic）',
    },
    'abi': {
        'modules': a['modules'], 'matched_symbols': a['matched_symbols'],
        'unique_crc_mismatch': len(uniq), 'missing_symbols': len(missing),
        'not_in_kernel_symvers': len(a['not_in_kernel_symvers']),
        'unclassified_missing_imports': len(a['unclassified_missing_imports']),
    },
    'hashes': {name: hashlib.sha256(Path('dist', name).read_bytes()).hexdigest()
               for name in (f'Image-{variant}', f'kernel-{variant}.config')},
}
Path(f'dist/build-{variant}.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n')
status = 'OK' if crc_rc == 0 else 'ABI_MISMATCH'
Path(f'dist/status-{variant}.txt').write_text(
    f"variant={variant}\nrelease={release}\nbuild=OK\nabi={status}\n"
    f"unique_crc_mismatch={len(uniq)}\n")
print("== build summary written")
PY
ls -la dist/
