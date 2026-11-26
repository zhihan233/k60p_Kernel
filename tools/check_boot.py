#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""本地校验 LOS 内核产物：boot.img header v4 / kernel_size / 版本串。"""
from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

PAGE = 4096


def check_boot(path: Path) -> int:
    data = path.read_bytes()
    magic = data[0:8]
    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from("<4I", data, 8)
    header_version = struct.unpack_from("<I", data, 40)[0]
    print(f"[boot] {path.name}: {len(data)} bytes")
    print(f"[boot] magic={magic!r} header_version={header_version} header_size={header_size}")
    print(f"[boot] kernel_size={kernel_size} ramdisk_size={ramdisk_size} os_version={os_version:#x}")
    ok = True
    if magic != b"ANDROID!":
        print("!! bad magic"); ok = False
    if header_version != 4:
        print(f"!! expected header_version 4, got {header_version}"); ok = False
    expected_total = (PAGE + kernel_size + PAGE - 1) // PAGE * PAGE
    if len(data) != expected_total:
        print(f"!! size mismatch: file={len(data)} expected={expected_total}"); ok = False
    else:
        print(f"[boot] size layout OK (header page + kernel + padding)")
    kernel = data[PAGE:PAGE + kernel_size]
    if kernel[56:60] != b"ARM\x64":
        print("!! embedded kernel is not arm64 Image"); ok = False
    else:
        print("[boot] embedded arm64 Image magic OK")
    m = re.search(rb"Linux version ([0-9][^\x00\s]{0,80})", kernel)
    ver = m.group(1).decode("ascii", "replace") if m else "NOT FOUND"
    print(f"[boot] embedded Linux version: {ver}")
    if not m:
        print("!! version string not found"); ok = False
    # 版本串不匹配只提示，不符预期时可人工判断
    return 0 if ok else 1


def check_image(path: Path) -> int:
    data = path.read_bytes()
    ok = data[56:60] == b"ARM\x64"
    print(f"[Image] {path.name}: {len(data)} bytes, arm64 magic={'OK' if ok else 'BAD'}")
    m = re.search(rb"Linux version ([0-9][^\x00\s]{0,80})", data)
    print(f"[Image] Linux version: {m.group(1).decode('ascii', 'replace') if m else 'NOT FOUND'}")
    return 0 if ok and m else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+", type=Path)
    args = ap.parse_args()
    rc = 0
    for p in args.paths:
        if not p.exists():
            print(f"!! missing {p}"); rc = 1; continue
        if p.suffix == ".img" and p.name.startswith("boot"):
            rc |= check_boot(p)
        elif p.name.startswith("Image"):
            rc |= check_image(p)
        else:
            print(f"[skip] {p} (unknown type)")
    return rc


if __name__ == "__main__":
    sys.exit(main())
