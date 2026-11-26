#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# 打包：boot.img（header v4）+ AnyKernel3 zip + SHA256SUMS + 发布说明
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VARIANT="${VARIANT:-los}"
mkdir -p dist

readarray -t META < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))
print(x['kernel']['release'])
print(x['anykernel3']['url'])
print(x['anykernel3']['commit'])
PY
)
RELEASE_STR="${META[0]}"; AK3_URL="${META[1]}"; AK3_COMMIT="${META[2]}"

[[ -f "dist/Image-${VARIANT}" ]] || { echo "!! dist/Image-${VARIANT} missing"; exit 1; }

echo "== building boot-${VARIANT}.img (header v4)"
python3 scripts/make_bootimg.py --kernel "dist/Image-${VARIANT}" --output "dist/boot-${VARIANT}.img"

echo "== building AnyKernel3 zip"
rm -rf .cache/anykernel3
mkdir -p .cache/anykernel3
git -C .cache/anykernel3 init -q
git -C .cache/anykernel3 remote add origin "${AK3_URL}"
git -C .cache/anykernel3 fetch -q --depth=1 origin "${AK3_COMMIT}"
git -C .cache/anykernel3 checkout -q --detach FETCH_HEAD
cp "dist/Image-${VARIANT}" .cache/anykernel3/Image
cp config/anykernel.sh .cache/anykernel3/anykernel.sh
cp "dist/build-${VARIANT}.json" "dist/abi-report-${VARIANT}.json" .cache/anykernel3/ 2>/dev/null || true
(
  cd .cache/anykernel3
  rm -rf .git
  zip -r9 "$ROOT/dist/ak3-${VARIANT}.zip" . -x '*.git*' -x 'README.md' >/dev/null
)

echo "== writing RELEASE note"
{
  echo "# K60 Pro (socrates) LineageOS 基线 5.15 定制内核 — ${RELEASE_STR}"
  echo
  echo "- 内核基线: LineageOS sm8550 (${RELEASE_STR})，与厂商 vendor 模块同源血统"
  echo "- 功能: Droidspaces（SYSVIPC kABI padding） + BBG 防格机 + 游戏/性能优化（MGLRU/fq_codel/BBR）"
  echo "- boot.img: Android boot header v4，kernel 偏移 4096，无 ramdisk/signature"
  echo
  echo "## 刷入"
  echo '```bash'
  echo "fastboot boot boot-${VARIANT}.img    # 先临时启动验证"
  echo "fastboot flash boot boot-${VARIANT}.img"
  echo '```'
  echo
  echo "回滚: fastboot flash boot <原厂 boot.img>"
  echo
  echo "## 自检"
  echo '```bash'
  echo "uname -r; lsmod | wc -l"
  echo "dmesg | grep -iE 'disagrees about version|Unknown symbol|CFI failure' | head"
  echo "cat /sys/kernel/security/lsm | tr ',' '\\n' | grep baseband"
  echo "cat /proc/sys/net/ipv4/tcp_congestion_control; cat /sys/kernel/mm/lru_gen/enabled"
  echo '```'
  echo
  echo "构建时间: $(date -u '+%Y-%m-%d %H:%M:%SZ')"
} > "dist/RELEASE-${VARIANT}.md"

echo "== SHA256SUMS"
(
  cd dist
  sha256sum "boot-${VARIANT}.img" "ak3-${VARIANT}.zip" "Image-${VARIANT}" > "SHA256SUMS-${VARIANT}"
  cat "SHA256SUMS-${VARIANT}"
)
ls -la dist/
