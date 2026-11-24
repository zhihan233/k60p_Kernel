#!/usr/bin/env bash
# 拉取固定版本内核源码与工具链，应用所有补丁。
# 环境变量: VARIANT=standard|gaming
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VARIANT="${VARIANT:-standard}"
mkdir -p dist kernel toolchain .cache

readarray -t LOCK < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))
k, t = x['kernel'], x['toolchain']
for v in (k['archive_url'], k['scmversion'], t['archive_url'], t['commit'], t['directory'], t['tree']):
    print(v)
PY
)
K_URL="${LOCK[0]}"; SCMVER="${LOCK[1]}"; T_URL="${LOCK[2]}"; T_COMMIT="${LOCK[3]}"; T_DIR="${LOCK[4]}"; T_TREE="${LOCK[5]}"

echo "== variant: ${VARIANT}"

# ---------- 1. kernel source ----------
if [[ ! -f kernel/Makefile ]]; then
  echo "== fetching kernel source: ${K_URL}"
  curl -fL --retry 3 "${K_URL}" -o .cache/kernel-source.tar.gz
  sha256sum .cache/kernel-source.tar.gz | tee dist/kernel-source.sha256
  mkdir -p kernel
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
  echo "== fetching toolchain: ${T_DIR}"
  mkdir -p "toolchain/${T_DIR}"
  curl -fL --retry 3 "${T_URL}" -o .cache/clang.tar.gz
  sha256sum .cache/clang.tar.gz > dist/compiler-archive.sha256
  tar -xzf .cache/clang.tar.gz -C "toolchain/${T_DIR}"
  rm -f .cache/clang.tar.gz
fi
"toolchain/${T_DIR}/bin/clang" --version | tee dist/compiler.txt

python3 - <<'PY'
import json, urllib.request
x = json.load(open('config/sources.lock.json'))['toolchain']
url = f"{x['url']}/+/{x['commit']}/{x['directory']}/?format=JSON"
with urllib.request.urlopen(url, timeout=60) as r:
    tree = json.loads(r.read()[4:])['id']
assert tree == x['tree'], (tree, x['tree'])
print("== toolchain tree verified")
PY

# ---------- 3. patches ----------
cd kernel
cp include/linux/sched.h ../.cache/sched.h.original
cp arch/arm64/configs/gki_defconfig ../.cache/gki_defconfig.original 2>/dev/null || true

SLOT=$(python3 ../scripts/pick_kabi_slot.py include/linux/sched.h | tee /dev/stderr | tail -1)
PATCHFILE="../patches/common/0001-sysvipc-kabi-padding-${SLOT}.patch"
if [[ ! -f "${PATCHFILE}" ]]; then
  echo "!! missing kABI padding patch for slot group ${SLOT}"
  exit 1
fi
echo "== kABI padding slot group: ${SLOT}"
patch --batch --fuzz=0 -p1 < "${PATCHFILE}"

apply_dir() {
  local dir="$1" p
  local found=0
  for p in "${dir}"/*.patch; do
    [[ -e "$p" ]] || continue
    # sysvipc kABI 补丁已按自动选槽单独应用，跳过所有备选变体
    case "$(basename "$p")" in
      0001-sysvipc-kabi-padding-*) continue ;;
    esac
    found=1
    echo "== applying $(basename "$p")"
    patch --batch --fuzz=3 -p1 < "$p"
  done
  [[ "$found" == 1 ]]
}

apply_dir ../patches/common
if [[ "${VARIANT}" == "gaming" ]]; then
  apply_dir ../patches/full
fi

# 不允许有被拒绝的 hunk
if find . -name '*.rej' | grep -q .; then
  echo "!! patch rejects found:"
  find . -name '*.rej'
  exit 1
fi

# ---------- 4. 精确复现原厂 vermagic ----------
printf '%s\n' "${SCMVER}" > .scmversion
cd ..

diff -u --label a/include/linux/sched.h --label b/include/linux/sched.h \
  .cache/sched.h.original kernel/include/linux/sched.h > dist/source.patch || test "$?" -eq 1 || true
cp config/sources.lock.json dist/
echo "== scmversion: $(cat kernel/.scmversion)"
echo "== disk:"
df -h .
du -sh kernel toolchain
