#!/usr/bin/env bash
# 发布：把构建产物推送到 ci-artifacts 分支（便于无 token 拉取），并上传到 GitHub Release。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
mkdir -p dist

echo "== collected files:"
ls -la dist/ || true

# ---------- 1. 汇总状态 ----------
{
  echo "# K60 Pro (socrates) kernel CI artifacts"
  echo
  echo "- run: ${GITHUB_RUN_ID:-local} / ${GITHUB_SHA:-local}"
  echo "- time: $(date -u)"
  echo
  for f in dist/status-*.txt; do
    [[ -e "$f" ]] || continue
    echo "## $(basename "$f")"
    cat "$f"
    echo
  done
} > dist/CI-SUMMARY.md

# ---------- 2. 推 ci-artifacts 分支（只放小文件） ----------
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git checkout --orphan ci-artifacts >/dev/null 2>&1 || true
git rm -rqf . --ignore-unmatch >/dev/null 2>&1 || true
mkdir -p ci-artifacts
find dist -maxdepth 2 -type f \( \
    -name '*.json' -o -name '*.txt' -o -name '*.diff' -o -name '*.config' \
    -o -name '*.md' -o -name '*.h' -o -name '*.sha256' -o -name 'SHA256SUMS-*' \
    -o -name '*.gz' -o -name '*.log' \) -exec cp {} ci-artifacts/ \; 2>/dev/null || true
echo "ci-artifacts branch content:"
ls -la ci-artifacts/ || true
git add -Af ci-artifacts >/dev/null
if git commit -qm "ci artifacts: run ${GITHUB_RUN_ID:-local}" >/dev/null 2>&1; then
  git push -f origin HEAD:ci-artifacts
else
  echo "== nothing to commit for ci-artifacts"
fi

# ---------- 3. GitHub Release ----------
if command -v gh >/dev/null 2>&1; then
  TAG="k60p-kernel-latest"
  NOTES=dist/CI-SUMMARY.md
  for f in dist/RELEASE-*.md; do
    [[ -e "$f" ]] && cat "$f" >> "$NOTES" && echo >> "$NOTES"
  done
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "K60 Pro (socrates) 5.15 kernel (latest CI build)" \
      --notes-file "$NOTES"
  fi
  # 可下载的产物
  shopt -s nullglob
  assets=(dist/boot-*.img dist/ak3-*.zip dist/Image-* dist/SHA256SUMS-* dist/build-*.json dist/kernel-*.config dist/abi-report-*.json)
  if ((${#assets[@]})); then
    gh release upload "$TAG" "${assets[@]}" --clobber
  fi
  gh release edit "$TAG" --notes-file "$NOTES" >/dev/null 2>&1 || true
else
  echo "!! gh CLI not available, skip release"
fi

echo "== publish done"
