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
print(k['archive_url'])
print(k['scmversion'])
print(t.get('archive_url', ''))
print(t.get('commit', ''))
print(t['directory'])
print(t.get('tree', ''))
print(t.get('fetch', 'archive'))
print(t.get('url', ''))
PY
)
K_URL="${LOCK[0]}"; SCMVER="${LOCK[1]}"; T_URL="${LOCK[2]}"; T_COMMIT="${LOCK[3]}"; T_DIR="${LOCK[4]}"; T_TREE="${LOCK[5]}"; T_FETCH="${LOCK[6]}"; T_REPO_URL="${LOCK[7]}"

echo "== variant: ${VARIANT}"

# ---------- 1. kernel source ----------
if [[ ! -f kernel/Makefile ]]; then
  echo "== fetching kernel source: ${K_URL}"
  curl -fL --retry 3 "${K_URL}" -o .cache/kernel-source.tar.gz
  sha256sum .cache/kernel-source.tar.gz | tee dist/kernel-source.sha256
  mkdir -p kernel
  # Gitiles +archive/<commit>.tar.gz 是「仓库树根」直接打包（没有顶层目录），
  # 不能使用 --strip-components=1，否则顶层文件（Makefile 等）会被丢掉。
  tar -xzf .cache/kernel-source.tar.gz -C kernel
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

# ---------- 1.5 生成 KMI 导出符号白名单 ----------
# 原厂 CONFIG_TRIM_UNUSED_KSYMS=y，靠白名单保留所有 KMI 导出符号（否则 vendor 模块
# 会因 "Unknown symbol" 加载失败）。白名单 = ACK android/abi_gki_aarch64* 全部符号列表，
# 与 Google GKI 构建使用的 KMI 符号集合一致。
python3 - <<'PY'
from pathlib import Path
kd = Path('kernel')
files = []
for p in sorted((kd / 'android').glob('abi_gki_aarch64*')):
    if p.suffix in ('.xml', '.stg', '.raw') or p.name.endswith('.allowed_breaks'):
        continue
    files.append(p)
syms = set()
for p in files:
    for line in p.read_text(errors='replace').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('['):
            continue
        if ' ' in line:
            continue
        syms.add(line)
assert len(syms) > 5000, f"KMI whitelist too small: {len(syms)}"
out = kd / 'kmi_whitelist.txt'
out.write_text('\n'.join(sorted(syms)) + '\n')
print(f"== KMI whitelist: {len(syms)} symbols from {len(files)} files -> {out}")
PY

# ---------- 2. toolchain ----------
if [[ ! -x "toolchain/${T_DIR}/bin/clang" ]]; then
  echo "== fetching toolchain: ${T_DIR} (${T_FETCH})"
  mkdir -p "toolchain/${T_DIR}"
  if [[ "${T_FETCH}" == "git-sparse" ]]; then
    # clang-r450784e 已从 prebuilts 仓库 HEAD 删除，需要：
    #   1) blobless clone（只有 commit/tree，无 blob）
    #   2) git log 找到最后包含该目录的 commit
    #   3) sparse-checkout 只拉该目录并 checkout
    rm -rf .cache/prebuilts-clang
    git clone --filter=blob:none --no-checkout "${T_REPO_URL}" .cache/prebuilts-clang
    (
      cd .cache/prebuilts-clang
      sha="$(git log -1 --format=%H -- "${T_DIR}")"
      echo "== ${T_DIR} last commit touching path: ${sha}"
      [[ -n "${sha}" ]] || { echo "!! cannot find ${T_DIR} in prebuilts history"; exit 1; }
      # 最后一个改动该路径的 commit 可能是「删除 clang-r450784e」的提交，
      # 需要沿 parent 回溯到仍包含该目录的 commit。
      while [[ -n "${sha}" ]] && ! git cat-file -e "${sha}:${T_DIR}" 2>/dev/null; do
        sha="$(git rev-parse "${sha}^" 2>/dev/null || true)"
      done
      [[ -n "${sha}" ]] || { echo "!! cannot locate a commit containing ${T_DIR}"; exit 1; }
      echo "== using commit containing ${T_DIR}: ${sha}"
      git sparse-checkout init --cone
      git sparse-checkout set "${T_DIR}"
      git checkout "${sha}"
      echo "${sha}" > "${ROOT}/dist/compiler-commit.txt"
    )
    cp -a ".cache/prebuilts-clang/${T_DIR}" "toolchain/${T_DIR}"
    rm -rf .cache/prebuilts-clang
  else
    curl -fL --retry 3 "${T_URL}" -o .cache/clang.tar.gz
    sha256sum .cache/clang.tar.gz > dist/compiler-archive.sha256
    tar -xzf .cache/clang.tar.gz -C "toolchain/${T_DIR}"
    rm -f .cache/clang.tar.gz
  fi
fi
"toolchain/${T_DIR}/bin/clang" --version | tee dist/compiler.txt

python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))['toolchain']
print(f"== toolchain: {x['directory']} ({x.get('fetch','archive')}), expected: {x.get('version','?')}")
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
