#!/usr/bin/env python3
"""Build an Android boot image header v4 (no ramdisk, no signature) for socrates.

Stock boot.img layout (Redmi K60 Pro, HyperOS 3.0.304):
  [4096-byte boot_img_hdr_v4][raw arm64 Image][page padding]
  followed by an AVB footer area at the end of the partition.

This script produces the clean, unsigned equivalent:
  [4096-byte header][Image][zero padding to page boundary]
which is what `fastboot flash boot` expects on an unlocked bootloader.
"""
from __future__ import annotations

import argparse
import struct
from pathlib import Path

PAGE_SIZE = 4096
HEADER_SIZE = 1584          # sizeof(struct boot_img_hdr_v4)
MAGIC = b"ANDROID!"


def build_header(kernel_size: int, kernel_addr: int, ramdisk_addr: int,
                 tags_addr: int, cmdline: bytes = b"",
                 os_version: int = 0) -> bytes:
    hdr = bytearray(PAGE_SIZE)
    hdr[0:8] = MAGIC
    struct.pack_into("<I", hdr, 8, kernel_size)
    struct.pack_into("<I", hdr, 12, 0)            # ramdisk_size
    struct.pack_into("<I", hdr, 16, os_version)   # os_version
    struct.pack_into("<I", hdr, 20, HEADER_SIZE)  # header_size
    struct.pack_into("<4I", hdr, 24, 0, 0, 0, 0)  # reserved
    struct.pack_into("<I", hdr, 40, 4)            # header_version = 4
    hdr[44:44 + min(len(cmdline), 1536)] = cmdline[:1536]
    struct.pack_into("<I", hdr, 1580, 0)          # signature_size = 0
    return bytes(hdr)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kernel", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--kernel-addr", type=lambda x: int(x, 0), default=0x80008000)
    ap.add_argument("--ramdisk-addr", type=lambda x: int(x, 0), default=0x82000000)
    ap.add_argument("--tags-addr", type=lambda x: int(x, 0), default=0x80000100)
    ap.add_argument("--cmdline", default="")
    ap.add_argument("--os-version", type=lambda x: int(x, 0), default=0)
    ap.add_argument("--pad-to", type=lambda x: int(x, 0), default=0,
                    help="pad output file to this many bytes (e.g. partition size)")
    args = ap.parse_args()

    kernel = args.kernel.read_bytes()
    if kernel[56:60] != b"ARM\x64":
        raise SystemExit(f"{args.kernel} does not look like an arm64 Image")
    header = build_header(len(kernel), args.kernel_addr, args.ramdisk_addr,
                          args.tags_addr, args.cmdline.encode(), args.os_version)
    out = bytearray(header)
    out += kernel
    while len(out) % PAGE_SIZE:
        out.append(0)
    if args.pad_to:
        if len(out) > args.pad_to:
            raise SystemExit(f"image ({len(out)}) larger than pad target ({args.pad_to})")
        out += b"\0" * (args.pad_to - len(out))
    args.output.write_bytes(out)
    print(f"== wrote {args.output} ({len(out)} bytes, kernel {len(kernel)} bytes)")


if __name__ == "__main__":
    main()
