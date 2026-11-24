#!/usr/bin/env bash
# 「最新 5.15」变体：ACK android13-5.15-lts (5.15.195) + upstream stable 5.15.226 三路合并，
# 再打 Droidspaces kABI / BBG / 游戏补丁 / vermagic 放宽补丁。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p dist
WORK="${WORKDIR:-$ROOT/work-latest}"
mkdir -p "$WORK"

ACK_SHA="8a8f52308945f4b0f1a168fa91bd7de0a76e59c4"
BASE_VER="5.15.195"
THEIRS_VER="5.15.226"
T_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/9916fb51ccb914d62d35ad9a7b9b21d2ef046928/clang-r563880c.tar.gz"
T_DIR="clang-r563880c"
T_TREE="571ed3e20b5708cea1177d5072853fc5b85b6877"

dl() {
  local url="$1" out="$2"
  [[ -s "$out" ]] && return 0
  echo "== download $out"
  curl -fsSL --retry 3 -o "$out.part" "$url"
  mv "$out.part" "$out"
}

echo "== 0. 下载源码 tarball"
cd "$WORK"
dl "https://codeload.github.com/aosp-mirror/kernel_common/tar.gz/$ACK_SHA" ack.tar.gz
dl "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$BASE_VER.tar.xz" base.tar.xz
dl "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$THEIRS_VER.tar.xz" theirs.tar.xz
df -h .

echo "== 1. 三提交仓库 + merge -X ours"
rm -rf repo
mkdir repo
cd repo
git init -q -b main
git config user.email ci@local
git config user.name ci
git config core.autocrlf false

tar -xJf ../base.tar.xz --strip-components=1
git add -A
git commit -qm "base: linux-$BASE_VER"
BASE_SHA="$(git rev-parse HEAD)"

git checkout -qb ack
git rm -rqf .
tar -xzf ../ack.tar.gz --strip-components=1
git add -A
git commit -qm "ack: kernel_common@$ACK_SHA"

git checkout -q "$BASE_SHA"
git checkout -qb theirs
git rm -rqf .
tar -xJf ../theirs.tar.xz --strip-components=1
git add -A
git commit -qm "theirs: linux-$THEIRS_VER"

git checkout -q ack
set +e
git merge -X ours --no-edit theirs > ../merge.log 2>&1
set -e
git diff --name-only --diff-filter=U > ../unmerged.txt || true
echo "== auto-merge conflicts resolved to ours: $(wc -l < ../unmerged.txt)"
cp ../unmerged.txt "$ROOT/dist/merge-conflicts-latest.txt"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if git checkout --ours -- "$f" 2>/dev/null; then
    git add -- "$f"
  else
    git rm -q -f -- "$f" 2>/dev/null || true
  fi
done < ../unmerged.txt
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  git commit -qm "merge: linux-$THEIRS_VER (-X ours)"
fi
git diff --stat ack HEAD | tail -1 > "$ROOT/dist/merge-diffstat-latest.txt"

# 5.15.225->226 上游把 sign-file/extract-cert 的 OpenSSL 兼容代码重构进
# scripts/ssl-common.h。ACK 侧这些文件与基线不同，三路合并 -X ours 会产生
# 半新半旧的混合体（#endif without #if / 函数重定义）。这些只是构建期 host 工具，
# 不影响内核代码，统一取 upstream(226) 侧版本保证自洽。
git checkout theirs -- scripts/sign-file.c scripts/extract-cert.c scripts/ssl-common.h 2>/dev/null || true
git commit -qm "merge fixup: use upstream 5.15.226 openssl host tools" >/dev/null 2>&1 || true
echo "== merge fixups applied (openssl host tools -> upstream 5.15.226 side)"

cd "$ROOT"
rm -rf kernel
mv "$WORK/repo" kernel
# git commit 可能触发后台 gc，直接 rm -rf 会偶发 "Directory not empty"，重试几次
for _i in 1 2 3 4; do
  rm -rf kernel/.git 2>/dev/null && break
  sleep 2
done || true
cp "$WORK/merge.log" dist/merge-latest.log
echo "scripts/sign-file.c scripts/extract-cert.c scripts/ssl-common.h (host openssl tools, upstream side)" > dist/merge-fixups-latest.txt

echo "== 1.5 生成 KMI 导出符号白名单"
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
assert len(syms) > 5000, len(syms)
(kd / 'kmi_whitelist.txt').write_text('\n'.join(sorted(syms)) + '\n')
print(f"== KMI whitelist: {len(syms)} symbols")
PY

echo "== 2. 应用补丁"
cd kernel
apply_one() {
  echo "== applying $(basename "$1")"
  patch --batch --fuzz=3 -p1 --forward < "$1"
}
apply_one "$ROOT/patches/common/0001-sysvipc-kabi-padding-6-7-8.patch"
apply_one "$ROOT/patches/common/0010-baseband-guard-5.15.patch"
for p in "$ROOT"/patches/common/00[2-9]*.patch; do
  apply_one "$p"
done
apply_one "$ROOT/patches/full/0030-net-tcp-bbrv3-android13-5.15.patch"
apply_one "$ROOT/.latest/vermagic-ignore.patch"
if find . -name '*.rej' | grep -q .; then
  echo "!! patch rejects:"
  find . -name '*.rej'
  exit 1
fi
cd "$ROOT"

echo "== 3. 工具链"
mkdir -p toolchain
if [[ ! -x "toolchain/$T_DIR/bin/clang" ]]; then
  dl "$T_URL" "$WORK/clang.tar.gz"
  mkdir -p "toolchain/$T_DIR"
  tar -xzf "$WORK/clang.tar.gz" -C "toolchain/$T_DIR"
  rm -f "$WORK/clang.tar.gz"
fi
"toolchain/$T_DIR/bin/clang" --version | tee dist/compiler.txt
python3 - <<PY
import json, urllib.request
url = "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/9916fb51ccb914d62d35ad9a7b9b21d2ef046928/$T_DIR/?format=JSON"
with urllib.request.urlopen(url, timeout=60) as r:
    tree = json.loads(r.read()[4:])["id"]
assert tree == "$T_TREE", (tree, "$T_TREE")
print("== toolchain tree verified")
PY

echo "== 4. 版本确认"
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) =' kernel/Makefile | tee dist/source-version-latest.txt
df -h .
du -sh kernel toolchain
