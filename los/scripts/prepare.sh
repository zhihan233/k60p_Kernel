#!/usr/bin/env bash
# 下载 LineageOS sm8550 内核源码 + AOSP clang，打补丁并准备构建环境。
# 运行目录: <repo>/los
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p dist kernel toolchain .cache

readarray -t LOCK < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))
k, t = x['kernel'], x['toolchain']
for v in (k['archive_url'], k['archive_sha256'], t['archive_url'], t['commit'],
          t['directory'], t['tree'], k['scmversion']):
    print(v)
PY
)
K_URL="${LOCK[0]}"; K_SHA="${LOCK[1]}"; T_URL="${LOCK[2]}"; T_COMMIT="${LOCK[3]}"
T_DIR="${LOCK[4]}"; T_TREE="${LOCK[5]}"; SCMVER="${LOCK[6]}"

echo "== LOS pipeline: kernel ${SCMVER}, toolchain ${T_DIR}"

# ---------- 1. kernel source ----------
if [[ ! -f kernel/Makefile ]]; then
  echo "== downloading LOS kernel source"
  curl -fL --retry 3 "${K_URL}" -o .cache/kernel-source.tar.gz
  printf '%s  %s\n' "${K_SHA}" .cache/kernel-source.tar.gz | sha256sum --check
  tar -xzf .cache/kernel-source.tar.gz --strip-components=1 -C kernel
  rm -f .cache/kernel-source.tar.gz
fi

python3 - <<'PY'
import json, re
from pathlib import Path
lock = json.load(open('config/sources.lock.json'))['kernel']
make = Path('kernel/Makefile').read_text()
want = lock['release'].split('-')[0]
got = '.'.join(re.search(rf'^{k} = (\d+)$', make, re.M).group(1)
               for k in ('VERSION', 'PATCHLEVEL', 'SUBLEVEL'))
print(f"== kernel source version: {got} (expect {want})")
assert got == want, (got, want)
PY

# ---------- 2. toolchain ----------
if [[ ! -x "toolchain/${T_DIR}/bin/clang" ]]; then
  echo "== downloading clang: ${T_DIR}"
  mkdir -p "toolchain/${T_DIR}"
  curl -fL --retry 3 "${T_URL}" -o .cache/clang.tar.gz
  sha256sum .cache/clang.tar.gz > dist/compiler-archive.sha256
  tar -xzf .cache/clang.tar.gz -C "toolchain/${T_DIR}"
  rm -f .cache/clang.tar.gz
fi

python3 scripts/verify_git_tree.py "toolchain/${T_DIR}" "${T_TREE}"
python3 - <<'PY'
import json, urllib.request
x = json.load(open('config/sources.lock.json'))['toolchain']
url = f"{x['url']}/+/{x['commit']}/{x['directory']}/?format=JSON"
with urllib.request.urlopen(url, timeout=60) as r:
    tree = json.loads(r.read()[4:])['id']
assert tree == x['tree'], (tree, x['tree'])
print("== toolchain tree verified")
PY
"toolchain/${T_DIR}/bin/clang" --version | tee dist/compiler.txt

# ---------- 3. patches ----------
cp kernel/include/linux/sched.h .cache/sched.h.original
cp kernel/arch/arm64/configs/gki_defconfig .cache/gki_defconfig.original
: > dist/patches-applied.txt
: > dist/patches-skipped.txt

# 所有补丁的路径都相对于内核源码根目录 (a/include/... / a/kernel/...)
apply_patch() {
  local p="$1" fuzz="$2" mode="$3" name
  name="$(basename "$p")"
  (
    cd kernel
    if patch --batch --fuzz="$fuzz" --dry-run < "../$p" >/dev/null 2>&1; then
      patch --batch --fuzz="$fuzz" < "../$p"
    else
      exit 3
    fi
  ) && echo "$name" >> dist/patches-applied.txt && return 0
  if [[ "$mode" == "hard" ]]; then
    echo "!! required patch failed to apply: $name"
    exit 1
  fi
  echo "$name" >> dist/patches-skipped.txt
  echo "-- skipped incompatible patch: $name"
}

echo "== applying SYSVIPC kABI padding (required)"
apply_patch patches/0001-sysvipc-kabi-padding-6-7-8.patch 0 hard
echo "== applying Baseband-guard (required)"
apply_patch patches/0010-baseband-guard-5.15.patch 3 hard
echo "== applying optional game/perf patches"
for p in patches/0020-*.patch patches/0021-*.patch patches/0022-*.patch \
         patches/0023-*.patch patches/0024-*.patch; do
  [[ -e "$p" ]] || continue
  apply_patch "$p" 3 soft
done

# ---------- 4. version string & source diff ----------
printf '%s\n' "$SCMVER" > kernel/.scmversion
{
  diff -u --label a/include/linux/sched.h --label b/include/linux/sched.h \
    .cache/sched.h.original kernel/include/linux/sched.h || test "$?" -eq 1 || true
  diff -u --label a/arch/arm64/configs/gki_defconfig --label b/arch/arm64/configs/gki_defconfig \
    .cache/gki_defconfig.original kernel/arch/arm64/configs/gki_defconfig || test "$?" -eq 1 || true
} > dist/source.patch
cp config/sources.lock.json dist/
echo "== applied patches:"; cat dist/patches-applied.txt 2>/dev/null || true
echo "== skipped patches:"; cat dist/patches-skipped.txt 2>/dev/null || true
df -h .
du -sh kernel toolchain
