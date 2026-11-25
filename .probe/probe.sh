#!/usr/bin/env bash
# ABI 探针：用不同 config / 编译器 组合构建内核，只做 vendor 模块 CRC 对比。
# 用法: probe.sh <name> <fragments,comma-separated> <toolchain: c21|c14> [lto: full|thin]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
NAME="$1"; FRAGMENTS="$2"; TOOLCHAIN="$3"; LTO="${4:-full}"
mkdir -p dist probe-work

STOCK_COMMIT="f4321180a3973d19b626b3eef51871199e4e1fac"
KERNEL_URL="https://android.googlesource.com/kernel/common/+archive/$STOCK_COMMIT.tar.gz"
if [[ "$TOOLCHAIN" == "c21" ]]; then
  T_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/9916fb51ccb914d62d35ad9a7b9b21d2ef046928/clang-r563880c.tar.gz"
  T_DIR="clang-r563880c"
elif [[ "$TOOLCHAIN" == "andr14" ]]; then
  T_DIR="clang-r450784e"
else
  T_DIR="clang14-symlinks"
fi

echo "== probe ${NAME}: fragments=${FRAGMENTS} toolchain=${TOOLCHAIN} lto=${LTO}"
df -h .

# ---------- 1. kernel source ----------
if [[ ! -f kernel/Makefile ]]; then
  echo "== download kernel source"
  curl -fsSL --retry 3 -o .cache-kernel.tar.gz "$KERNEL_URL"
  mkdir -p kernel
  tar -xzf .cache-kernel.tar.gz -C kernel
  rm -f .cache-kernel.tar.gz
fi

# ---------- 2. toolchain ----------
if [[ "$TOOLCHAIN" == "c21" ]]; then
  if [[ ! -x "toolchain/$T_DIR/bin/clang" ]]; then
    mkdir -p "toolchain/$T_DIR"
    curl -fsSL --retry 3 -o .cache-clang.tar.gz "$T_URL"
    tar -xzf .cache-clang.tar.gz -C "toolchain/$T_DIR"
    rm -f .cache-clang.tar.gz
  fi
  export PATH="$ROOT/toolchain/$T_DIR/bin:$PATH"
elif [[ "$TOOLCHAIN" == "andr14" ]]; then
  if [[ ! -x "toolchain/$T_DIR/bin/clang" ]]; then
    echo "== sparse clone Android clang r450784e"
    rm -rf .clang-prec
    git clone --depth 1 --filter=blob:none --sparse \
      https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 .clang-prec
    ( cd .clang-prec && git sparse-checkout set clang-r450784e )
    mv .clang-prec/clang-r450784e toolchain/
    rm -rf .clang-prec
  fi
  export PATH="$ROOT/toolchain/$T_DIR/bin:$PATH"
else
  mkdir -p "toolchain/$T_DIR"
  for t in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-strip; do
    src="/usr/bin/${t}-14"
    [[ -x "$src" ]] || { echo "!! missing $src"; exit 1; }
    ln -sf "$src" "toolchain/$T_DIR/$t"
  done
  export PATH="$ROOT/toolchain/$T_DIR:$PATH"
fi
echo "== clang: $(clang --version | head -1)"

# ---------- 3. patches ----------
cd kernel
cp include/linux/sched.h ../.cache-sched.h
patch --batch --fuzz=0 -p1 < ../patches/common/0001-sysvipc-kabi-padding-6-7-8.patch
for p in ../patches/common/0010-*.patch ../patches/common/00[2-9]*.patch ../patches/full/*.patch; do
  [[ -e "$p" ]] || continue
  echo "== patch $(basename "$p")"
  patch --batch --fuzz=3 -p1 < "$p"
done
if find . -name '*.rej' | grep -q .; then echo "!! patch rejects"; find . -name '*.rej'; exit 1; fi
cd ..

# ---------- 4. KMI whitelist ----------
python3 - <<'PY'
from pathlib import Path
kd = Path('kernel')
syms = set()
files = 0
for p in sorted((kd / 'android').glob('abi_gki_aarch64*')):
    if p.suffix in ('.xml', '.stg', '.raw') or p.name.endswith('.allowed_breaks'):
        continue
    files += 1
    for line in p.read_text(errors='replace').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('[') or ' ' in line:
            continue
        syms.add(line)
assert len(syms) > 5000
(kd / 'kmi_whitelist.txt').write_text('\n'.join(sorted(syms)) + '\n')
print(f"== KMI whitelist: {len(syms)} symbols from {files} files")
PY

# ---------- 5. config ----------
mkdir -p out
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
      \"*\") val="${val#\"}"; val="${val%\"}"; kernel/scripts/config --file out/.config --set-str "$sym" "$val" ;;
      *) kernel/scripts/config --file out/.config --set-val "$sym" "$val" ;;
    esac
  done < "$1"
}
IFS=',' read -ra FRAG_ARR <<< "$FRAGMENTS"
for f in "${FRAG_ARR[@]}"; do
  [[ -n "$f" ]] || continue
  echo "== fragment $f"
  apply_cfg "$f"
done
# BBG 默认 CONFIG_BBG=y（Kconfig default），必须在 CONFIG_LSM 里加入 baseband_guard，
# 否则 security/baseband-guard/Makefile 会 $(error) 终止构建。
kernel/scripts/config --file out/.config --set-str LSM "landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,baseband_guard,smack,tomoyo,apparmor,bpf"
kernel/scripts/config --file out/.config --enable TRIM_UNUSED_KSYMS
kernel/scripts/config --file out/.config --set-str UNUSED_KSYMS_WHITELIST "$ROOT/kernel/kmi_whitelist.txt"
if [[ "$LTO" == "thin" ]]; then
  kernel/scripts/config --file out/.config --enable LTO_CLANG_THIN --disable LTO_CLANG_FULL
else
  kernel/scripts/config --file out/.config --enable LTO_CLANG_FULL --disable LTO_CLANG_THIN
fi

export ARCH=arm64 LLVM=1 LLVM_IAS=1
if [[ -n "${PROBE_KCFLAGS:-}" ]]; then
  export KCFLAGS="$PROBE_KCFLAGS"
  echo "== KCFLAGS: $KCFLAGS"
fi
export CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KBUILD_BUILD_USER=probe KBUILD_BUILD_HOST=ci
export LOCALVERSION="-android13-8"
export BUILD_NUMBER=15212794
make -C kernel O="$ROOT/out" olddefconfig
cp out/.config "dist/probe-${NAME}.config"

# ---------- 6. build ----------
echo "== build"
set +e
make -C kernel O="$ROOT/out" -j"$(nproc)" Image modules > "dist/probe-${NAME}.log" 2>&1
rc=$?
set -e
if [[ "$rc" != 0 ]]; then
  echo "!! build failed rc=$rc"
  grep -n -i -E 'error:|fatal error|undefined reference|No rule to make|Killed' "dist/probe-${NAME}.log" | head -n 100 || true
  tail -n 80 "dist/probe-${NAME}.log" || true
  echo "BUILD_FAILED" > "dist/probe-${NAME}.status"
  exit 1
fi

# ---------- 7. CRC 对比 ----------
set +e
python3 scripts/check_module_abi.py "out/Module.symvers" evidence/vendor-module-versions.json \
  --report "dist/probe-${NAME}.abi.json"
crc_rc=$?
set -e
cp out/Module.symvers "dist/probe-${NAME}.symvers"
{
  echo "probe=${NAME}"
  echo "fragments=${FRAGMENTS}"
  echo "toolchain=${TOOLCHAIN}"
  echo "lto=${LTO}"
  echo "clang=$(clang --version | head -1)"
  echo "abi_rc=${crc_rc}"
  echo "result=$( [[ $crc_rc == 0 ]] && echo ABI_OK || echo ABI_MISMATCH )"
} > "dist/probe-${NAME}.status"
cat "dist/probe-${NAME}.status"
python3 - "dist/probe-${NAME}.abi.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
missing = [m for m in j['crc_mismatches'] if m['built_crc'] == 'MISSING']
real = [m for m in j['crc_mismatches'] if m['built_crc'] != 'MISSING']
print(f"modules={j['modules']} matched={j['matched_symbols']} missing={len(missing)} real_crc_mismatch={len(real)}")
print("sample_real:", [m['symbol'] for m in real[:10]])
PY

# 小文件推到独立分支
git config user.name probe
git config user.email probe@local
git checkout --orphan "abi-probe-${NAME}" >/dev/null 2>&1 || true
git rm -rqf . --ignore-unmatch >/dev/null 2>&1 || true
mkdir -p probe
cp dist/probe-* probe/ 2>/dev/null || true
git add -Af probe >/dev/null
git commit -qm "abi probe ${NAME}" >/dev/null
git push -f origin "HEAD:abi-probe-${NAME}"
echo "== probe ${NAME} done"
