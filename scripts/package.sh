#!/usr/bin/env bash
# 打包 Image / boot.img / AnyKernel3 ZIP，并收集 CI 诊断文件。
# 环境变量: VARIANT=standard|gaming
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VARIANT="${VARIANT:-standard}"
mkdir -p dist dist/ci-artifacts

collect_logs() {
  mkdir -p dist/ci-artifacts
  for lf in dist/*.log; do
    [[ -e "$lf" ]] && cp "$lf" "dist/ci-artifacts/" 2>/dev/null || true
  done
  for extra in "dist/config-${VARIANT}.diff" "dist/kernel-${VARIANT}.config" \
               "dist/utsrelease-${VARIANT}.h" "dist/compiler.txt" \
               "dist/kernel-source.sha256" "dist/source.patch" "dist/sources.lock.json"; do
    [[ -e "$extra" ]] && cp "$extra" "dist/ci-artifacts/" 2>/dev/null || true
  done
}
collect_logs

if [[ ! -f "dist/Image-${VARIANT}" ]]; then
  echo "!! no kernel Image built for variant ${VARIANT}, skip packaging"
  echo "NO_IMAGE" > "dist/ci-artifacts/status-${VARIANT}.txt"
  exit 0
fi

# ---------- 1. boot.img ----------
python3 scripts/make_bootimg.py \
  --kernel "dist/Image-${VARIANT}" \
  --output "dist/boot-${VARIANT}.img"

# ---------- 2. AnyKernel3 ZIP ----------
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
cp config/anykernel.sh .cache/anykernel3/anykernel.sh
cp "dist/build-${VARIANT}.json" .cache/anykernel3/build.json 2>/dev/null || true
(
  cd .cache/anykernel3
  rm -f .github .git -rf
  zip -r9 "$ROOT/dist/ak3-${VARIANT}.zip" . -x '.git/*' '.github/*' 'README.md'
)

# ---------- 3. checksums ----------
(
  cd dist
  sha256sum "Image-${VARIANT}" "boot-${VARIANT}.img" "ak3-${VARIANT}.zip" \
    > "SHA256SUMS-${VARIANT}"
)

# ---------- 4. CI 诊断文件（推到 ci-artifacts 分支，方便排查） ----------
cp "dist/config-${VARIANT}.diff" "dist/ci-artifacts/" 2>/dev/null || true
cp "dist/kernel-${VARIANT}.config" "dist/ci-artifacts/" 2>/dev/null || true
cp "dist/abi-report-${VARIANT}.json" "dist/ci-artifacts/" 2>/dev/null || true
cp "dist/build-${VARIANT}.json" "dist/ci-artifacts/" 2>/dev/null || true
cp "dist/SHA256SUMS-${VARIANT}" "dist/ci-artifacts/" 2>/dev/null || true
cp "dist/utsrelease-${VARIANT}.h" "dist/ci-artifacts/" 2>/dev/null || true
cp dist/compiler.txt "dist/ci-artifacts/" 2>/dev/null || true
cp dist/kernel-source.sha256 "dist/ci-artifacts/" 2>/dev/null || true
cp dist/source.patch "dist/ci-artifacts/" 2>/dev/null || true
cp dist/sources.lock.json "dist/ci-artifacts/" 2>/dev/null || true
for lf in dist/*.log; do
  [[ -e "$lf" ]] && cp "$lf" "dist/ci-artifacts/" 2>/dev/null || true
done
if [[ -f dist/build.log ]]; then
  # 只保留错误摘要 + 尾部，避免分支过大
  {
    echo "=== error lines ==="
    grep -n -i -E 'error:|warning: .*\[-W|fatal error|undefined' dist/build.log | head -n 200 || true
    echo
    echo "=== tail 300 ==="
    tail -n 300 dist/build.log || true
  } > "dist/ci-artifacts/build-${VARIANT}-summary.txt"
fi

# 生成给人看的发布说明
python3 - "${VARIANT}" <<'PY'
import json, sys
from pathlib import Path
variant = sys.argv[1]
info = json.loads(Path(f'dist/build-{variant}.json').read_text()) if Path(f'dist/build-{variant}.json').exists() else {}
lines = [
    f"## {variant} 内核",
    "",
    f"- 设备: {info.get('device_name','Redmi K60 Pro')} ({info.get('device','socrates')})",
    f"- ROM: {info.get('rom','HyperOS 3.0.304.0 / Android 16')}",
    f"- 内核版本: `{info.get('kernel_release','?')}` (vermagic 与原厂完全一致)",
    f"- 工具链: {info.get('toolchain',{}).get('version','?')}",
    f"- 功能: Droidspaces 容器支持 / BBG 防格机 / {'BBRv3+fq_codel+游戏优化' if variant=='gaming' else 'BBR+fq_codel 游戏优化'}",
    f"- 原厂 vendor 模块 CRC 对比: {info.get('vendor_module_crc_check','?')} (告警模式：运行时不匹配会打印到 dmesg)",
    "",
]
Path(f'dist/RELEASE-{variant}.md').write_text('\n'.join(lines))
PY

ls -la dist/
