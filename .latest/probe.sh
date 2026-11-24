#!/usr/bin/env bash
# 轻量探针：只做「ACK 5.15.195 + upstream stable 5.15.226 三路合并 + 补丁应用 + 配置生成」，
# 不编译内核（约 10-15 分钟），用于评估「最新 5.15」变体的可行性。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/probe-out"
mkdir -p "$OUT"
exec > >(tee -a "$OUT/probe.log") 2>&1

ACK_SHA="8a8f52308945f4b0f1a168fa91bd7de0a76e59c4"   # android13-5.15-lts head (5.15.195)
BASE_VER="5.15.195"
THEIRS_VER="5.15.226"

WORK="${WORKDIR:-$RUNNER_TEMP/socrates-probe}"
mkdir -p "$WORK"
cd "$WORK"

log() { echo; echo "===== $* ====="; }

log "0. 下载源码 tarball"
[[ -s ack.tar.gz ]] || curl -fsSL --retry 3 -o ack.tar.gz "https://codeload.github.com/aosp-mirror/kernel_common/tar.gz/$ACK_SHA"
[[ -s base.tar.xz ]] || curl -fsSL --retry 3 -o base.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$BASE_VER.tar.xz"
[[ -s theirs.tar.xz ]] || curl -fsSL --retry 3 -o theirs.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$THEIRS_VER.tar.xz"
ls -la ack.tar.gz base.tar.xz theirs.tar.xz
df -h .

log "1. 构建三提交仓库 (base=5.15.195, ack=ACK lts, theirs=5.15.226)"
rm -rf repo
mkdir repo
cd repo
git init -q -b main
git config user.email probe@local
git config user.name probe
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

log "2. git merge -X ours theirs"
git checkout -q ack
set +e
git merge -X ours --no-edit theirs > "$OUT/merge.log" 2>&1
merge_rc=$?
set -e
echo "merge rc=$merge_rc"
git diff --name-only --diff-filter=U > "$OUT/unmerged.txt" || true
echo "unmerged files after -X ours: $(wc -l < "$OUT/unmerged.txt")"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if git checkout --ours -- "$f" 2>/dev/null; then
    git add -- "$f"
  else
    git rm -q -f -- "$f" 2>/dev/null || true
  fi
done < "$OUT/unmerged.txt"
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  git commit -qm "merge: linux-$THEIRS_VER (-X ours)"
fi
echo "== 合并后相对 ACK 的改动统计:"
git diff --stat ack HEAD | tail -3 | tee "$OUT/summary.txt"
echo "== 冲突文件（已按 ours 解决）:" >> "$OUT/summary.txt"
cat "$OUT/unmerged.txt" >> "$OUT/summary.txt"
head -3 Makefile | tee -a "$OUT/summary.txt"

log "3. 应用补丁（sysvipc kABI / BBG / 游戏小补丁 / BBRv3）"
PATCH_LOG="$OUT/patch-apply.log"
: > "$PATCH_LOG"
apply_one() {
  local p="$1"
  local fuzz="${2:-3}"
  echo "== $(basename "$p") fuzz=$fuzz" | tee -a "$PATCH_LOG"
  set +e
  patch --batch --fuzz="$fuzz" -p1 --forward < "$p" >> "$PATCH_LOG" 2>&1
  local rc=$?
  set -e
  echo "   rc=$rc (rejects total: $(find . -name '*.rej' | wc -l))" | tee -a "$PATCH_LOG"
}
apply_one "$ROOT/patches/common/0001-sysvipc-kabi-padding-6-7-8.patch" 3
apply_one "$ROOT/patches/common/0010-baseband-guard-5.15.patch" 3
for p in "$ROOT"/patches/common/00[2-9]*.patch; do
  apply_one "$p" 3
done
apply_one "$ROOT/patches/full/0030-net-tcp-bbrv3-android13-5.15.patch" 3

log "4. 收集 rejects"
find . -name '*.rej' | sort > "$OUT/rejects.txt"
echo "rejects: $(wc -l < "$OUT/rejects.txt")" | tee -a "$OUT/summary.txt"
if [[ -s "$OUT/rejects.txt" ]]; then
  tar -czf "$OUT/rejects.tar.gz" -T "$OUT/rejects.txt"
  echo "== reject 文件列表:" | tee -a "$OUT/summary.txt"
  cat "$OUT/rejects.txt" >> "$OUT/summary.txt"
fi

log "5. 生成 .config 并 olddefconfig"
mkdir -p out
cp "$ROOT/config/device-baseline.config" out/.config
apply_cfg() {
  local line sym val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
      '') continue ;;
      '#'*)
        if [[ "$line" == "# CONFIG_"*" is not set" ]]; then
          sym="${line#\# CONFIG_}"; sym="${sym%% is not set*}"
          ./scripts/config --file out/.config --disable "$sym"
        fi
        continue ;;
    esac
    [[ "$line" == CONFIG_*=* ]] || continue
    sym="${line%%=*}"; val="${line#*=}"
    case "$val" in
      y) ./scripts/config --file out/.config --enable "$sym" ;;
      n) ./scripts/config --file out/.config --disable "$sym" ;;
      \"*\")
        val="${val#\"}"; val="${val%\"}"
        ./scripts/config --file out/.config --set-str "$sym" "$val" ;;
      *) ./scripts/config --file out/.config --set-val "$sym" "$val" ;;
    esac
  done < "$1"
}
apply_cfg "$ROOT/config/features-common.config"
apply_cfg "$ROOT/config/features-gaming.config"
./scripts/config --file out/.config --disable UNUSED_KSYMS_WHITELIST
export ARCH=arm64
make O=out olddefconfig > "$OUT/olddefconfig.log" 2>&1
./scripts/diffconfig "$ROOT/config/device-baseline.config" out/.config > "$OUT/config.diff" || true
cp out/.config "$OUT/kernel.config"
echo "== config diff (前 40 行):" >> "$OUT/summary.txt"
head -40 "$OUT/config.diff" >> "$OUT/summary.txt"

log "6. 探针结果"
echo "DONE" >> "$OUT/summary.txt"
cat "$OUT/summary.txt"
df -h .
