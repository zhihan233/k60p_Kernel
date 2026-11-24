#!/usr/bin/env bash
# GitHub Actions ubuntu-24.04 runner 准备：清理无用预装目录、安装内核构建依赖。
set -euo pipefail
echo "== runner: ${ImageOS:-unknown} / $(uname -a)"
df -h /
free -h

# 清理 runner 上体积大且与本次构建无关的预装组件，腾出磁盘供 Full LTO 使用
for d in /usr/local/lib/android /usr/share/dotnet /opt/ghc /opt/hostedtoolcache/CodeQL \
         /usr/local/.ghcup /usr/local/share/powershell /usr/share/swift; do
  if [ -e "$d" ]; then
    echo "== removing $d"
    sudo rm -rf "$d" || true
  fi
done

echo "== disk after cleanup"
df -h /

sudo apt-get update -qq -o Acquire::Retries=3 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60
sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
  apt-get install -y --no-install-recommends \
  bc bison flex libssl-dev libelf-dev dwarves cpio build-essential patch \
  zip unzip curl git python3 lz4 zstd kmod openssl file pkg-config
sudo apt-get clean

echo "== installed tools"
for t in clang gcc make bison flex pahole openssl zip; do
  command -v "$t" >/dev/null 2>&1 && echo "  $t: $(command -v "$t")" || echo "  $t: MISSING"
done

echo "== final disk"
df -h /
free -h
