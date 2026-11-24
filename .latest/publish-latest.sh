#!/usr/bin/env bash
# 「最新 5.15.226」变体发布：latest-artifacts 分支 + Release k60p-kernel-5.15.226
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p dist
ls -la dist/ || true

{
  echo "# K60 Pro (socrates) 5.15.226 latest kernel artifacts"
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

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git checkout --orphan latest-artifacts >/dev/null 2>&1 || true
git rm -rqf . --ignore-unmatch >/dev/null 2>&1 || true
mkdir -p latest-artifacts
find dist -maxdepth 2 -type f \( \
    -name '*.json' -o -name '*.txt' -o -name '*.diff' -o -name '*.config' \
    -o -name '*.md' -o -name '*.h' -o -name '*.log' -o -name '*.sha256' \
    -o -name 'SHA256SUMS-*' -o -name '*.gz' \) -exec cp {} latest-artifacts/ \; 2>/dev/null || true
git add -Af latest-artifacts >/dev/null
if git commit -qm "latest artifacts: run ${GITHUB_RUN_ID:-local}" >/dev/null 2>&1; then
  git push -f origin HEAD:latest-artifacts
fi

if command -v gh >/dev/null 2>&1; then
  set +e
  TAG="k60p-kernel-5.15.226"
  NOTES=dist/CI-SUMMARY.md
  cat dist/RELEASE-latest.md >> "$NOTES" 2>/dev/null || true
  if ! gh release view "$TAG" >/dev/null 2>&1; then
    gh release create "$TAG" --title "K60 Pro (socrates) 5.15.226 内核 (latest 5.15)" --notes-file "$NOTES"
  fi
  shopt -s nullglob
  assets=(dist/boot-latest.img dist/ak3-latest.zip dist/Image-latest dist/SHA256SUMS-latest dist/build-latest.json dist/kernel-latest.config dist/abi-report-latest.json)
  if ((${#assets[@]})); then
    gh release upload "$TAG" "${assets[@]}" --clobber
  fi
  gh release edit "$TAG" --notes-file "$NOTES" >/dev/null 2>&1 || true
  set -e
fi
echo "== latest publish done"
