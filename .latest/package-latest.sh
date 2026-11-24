#!/usr/bin/env bash
# 「最新 5.15.226」变体打包：Image / boot.img / AnyKernel3 / 校验和 / 诊断。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VARIANT="latest"
mkdir -p dist dist/ci-artifacts

if [[ ! -f "dist/Image-${VARIANT}" ]]; then
  echo "!! no Image built for variant ${VARIANT}, skip packaging"
  for lf in dist/*.log; do
    [[ -e "$lf" ]] && cp "$lf" "dist/ci-artifacts/" 2>/dev/null || true
  done
  echo "NO_IMAGE" > "dist/ci-artifacts/status-${VARIANT}.txt"
  exit 0
fi

python3 scripts/make_bootimg.py \
  --kernel "dist/Image-${VARIANT}" \
  --output "dist/boot-${VARIANT}.img"

readarray -t AK3 < <(python3 - <<'PY'
import json
x = json.load(open('config/sources.lock.json'))['anykernel3']
print(x['url']); print(x['commit'])
PY
)
rm -rf .cache/anykernel3
mkdir -p .cache/anykernel3
git init -q .cache/anykernel3
git -C .cache/anykernel3 remote add origin "${AK3[0]}"
git -C .cache/anykernel3 fetch -q --depth=1 origin "${AK3[1]}"
git -C .cache/anykernel3 checkout -q --detach FETCH_HEAD
cp "dist/Image-${VARIANT}" .cache/anykernel3/Image
cp ".latest/anykernel-latest.sh" .cache/anykernel3/anykernel.sh
cp "dist/build-${VARIANT}.json" .cache/anykernel3/build.json 2>/dev/null || true
(
  cd .cache/anykernel3
  rm -rf .github .git
  zip -r9 "$ROOT/dist/ak3-${VARIANT}.zip" . -x '.github/*' 'README.md'
)

(
  cd dist
  sha256sum "Image-${VARIANT}" "boot-${VARIANT}.img" "ak3-${VARIANT}.zip" > "SHA256SUMS-${VARIANT}"
)

for f in "config-${VARIANT}.diff" "kernel-${VARIANT}.config" "abi-report-${VARIANT}.json" \
         "build-${VARIANT}.json" "utsrelease-${VARIANT}.h" "release-${VARIANT}.txt" \
         "merge-conflicts-${VARIANT}.txt" "merge-diffstat-${VARIANT}.txt" \
         "merge-${VARIANT}.log" "source-version-${VARIANT}.txt"; do
  [[ -e "dist/$f" ]] && cp "dist/$f" "dist/ci-artifacts/" 2>/dev/null || true
done
cp dist/compiler.txt "dist/ci-artifacts/" 2>/dev/null || true
for lf in dist/*.log; do
  [[ -e "$lf" ]] && cp "$lf" "dist/ci-artifacts/" 2>/dev/null || true
done
if [[ -f dist/build-latest.log ]]; then
  {
    echo "=== error lines ==="
    grep -n -i -E 'error:|warning: .*\[-W|fatal error|undefined' dist/build-latest.log | head -n 200 || true
    echo
    echo "=== tail 300 ==="
    tail -n 300 dist/build-latest.log || true
  } > "dist/ci-artifacts/build-${VARIANT}-summary.txt"
fi

{
  echo "## latest 5.15.226 内核"
  echo
  echo "- 设备: Redmi K60 Pro (socrates), HyperOS 3.0.304.0 / Android 16"
  echo "- 源码: ACK android13-5.15-lts (5.15.195) + upstream stable 5.15.226 合并 (-X ours)"
  echo "- 内核版本: $(cat "dist/release-${VARIANT}.txt" 2>/dev/null || echo '?')（vermagic 放宽补丁）"
  echo "- 特性: Droidspaces 容器 + BBG 防格机 + BBRv3 默认 + fq_codel + MGLRU + 游戏补丁"
  echo "- 原厂 vendor 模块 CRC: $(python3 -c "import json;print(json.load(open('dist/build-${VARIANT}.json'))['vendor_module_crc_check'])" 2>/dev/null || echo '?')"
  echo "- 冲突文件（保留 ACK 侧）: $(cat "dist/merge-conflicts-${VARIANT}.txt" 2>/dev/null | tr '\n' ' ')"
} > "dist/RELEASE-${VARIANT}.md"

ls -la dist/
