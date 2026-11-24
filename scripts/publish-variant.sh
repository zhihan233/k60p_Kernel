#!/usr/bin/env bash
# 单个变体构建完成后立即发布（不依赖其他 matrix 任务），避免某个变体卡住导致全部产物无法发布。
# 环境变量: VARIANT=standard|gaming ; GH_TOKEN
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VARIANT="${VARIANT:?VARIANT required}"
mkdir -p dist

collect_small() {
  local dest="$1"
  mkdir -p "$dest"
  for f in "status-${VARIANT}.txt" "steps-${VARIANT}.txt" "build-${VARIANT}.json" \
           "kernel-${VARIANT}.config" "config-${VARIANT}.diff" "abi-report-${VARIANT}.json" \
           "SHA256SUMS-${VARIANT}" "utsrelease-${VARIANT}.h" "compiler.txt" \
           "kernel-source.sha256" "source.patch" "RELEASE-${VARIANT}.md"; do
    [[ -e "dist/$f" ]] && cp "dist/$f" "$dest/" 2>/dev/null || true
  done
  for lf in dist/*.log; do
    [[ -e "$lf" ]] && cp "$lf" "$dest/" 2>/dev/null || true
  done
  for lf in dist/ci-artifacts/*; do
    [[ -e "$lf" ]] && cp "$lf" "$dest/" 2>/dev/null || true
  done
}

echo "== publish variant: ${VARIANT}"
ls -la dist/ | head -40

# 1) 小文件推到独立分支，便于无 token 排查
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git checkout --orphan "artifacts-${VARIANT}" >/dev/null 2>&1 || true
git rm -rqf . --ignore-unmatch >/dev/null 2>&1 || true
collect_small "artifacts-${VARIANT}"
git add -Af "artifacts-${VARIANT}" >/dev/null
if git commit -qm "artifacts ${VARIANT}: run ${GITHUB_RUN_ID:-local}"; then
  git push -f origin "HEAD:artifacts-${VARIANT}"
fi

# 2) 可下载产物上传到 Release
if [[ -f "dist/Image-${VARIANT}" ]] && command -v gh >/dev/null 2>&1; then
  TAG="k60p-kernel-v2"
  NOTES="dist/RELEASE-${VARIANT}.md"
  [[ -f "$NOTES" ]] || echo "# K60 Pro kernel build" > "$NOTES"
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "K60 Pro (socrates) 5.15 定制内核" --notes-file "$NOTES"
  fi
  set +e
  gh release upload "$TAG" \
    "dist/boot-${VARIANT}.img" "dist/ak3-${VARIANT}.zip" "dist/Image-${VARIANT}" \
    "dist/SHA256SUMS-${VARIANT}" "dist/build-${VARIANT}.json" \
    "dist/kernel-${VARIANT}.config" "dist/abi-report-${VARIANT}.json" --clobber
  rc=$?
  set -e
  [[ "$rc" == 0 ]] && echo "== release assets uploaded (${VARIANT})" || echo "!! release upload failed rc=$rc"
fi

echo "== publish done (${VARIANT})"
