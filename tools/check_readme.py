#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""仓库文档自检：README 表格列数、代码块内文件引用、常见过期表述。

用法：python tools/check_readme.py [README.md]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


def check_tables(lines: list[str]) -> int:
    bad = 0
    i = 0
    while i < len(lines):
        if lines[i].strip().startswith('|'):
            rows = []
            j = i
            while j < len(lines) and lines[j].strip().startswith('|'):
                rows.append((j + 1, lines[j].count('|')))
                j += 1
            cols = {c for _, c in rows}
            if len(cols) > 1:
                bad += 1
                print(f'FAIL table at line {i + 1}: inconsistent columns {rows}')
            i = j
        else:
            i += 1
    return bad


def expand_braces(ref: str) -> list[str]:
    m = re.match(r'^(.*)\{([^{}]+)\}(.*)$', ref)
    if not m:
        return [ref]
    prefix, body, suffix = m.groups()
    return [prefix + item + suffix for item in body.split(',')]


def check_refs(root: Path, text: str) -> int:
    missing = 0
    refs = set(re.findall(r'`([^`]+)`', text))
    for ref in sorted(refs):
        ref = ref.strip()
        if not ref or ref.startswith('http') or ref.startswith('/'):
            continue
        if any(ch in ref for ch in ('*', '?', '$', '|', '<', '>', '=', '\\', ' ')):
            continue
        if '/' not in ref:
            continue
        for candidate in expand_braces(ref):
            candidate = candidate.rstrip('/')
            if not candidate:
                continue
            if not (root / candidate).exists():
                missing += 1
                print(f'FAIL missing referenced path: {candidate}')
    return missing


def check_stale(text: str) -> int:
    rules = {
        'stale claim "401 个原厂模块"': '401 个原厂模块' in text,
        'stale claim "自写补丁"': '自写补丁' in text,
        'stale link docs/': '](docs/' in text,
        'stale rollback name stock-boot_a.img in commands': 'fastboot flash boot stock-boot_a.img' in text
        and 'stock-boot.img' in text,
        'missing securityfs mkdir': 'mkdir -p /sys/kernel/security' not in text and 'securityfs' in text,
        'missing LICENSE link': '](LICENSE)' not in text,
    }
    bad = 0
    for name, hit in rules.items():
        if hit:
            bad += 1
            print(f'FAIL {name}')
    return bad


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'README.md'
    text = target.read_text(encoding='utf-8')
    lines = text.splitlines()
    failures = check_tables(lines) + check_refs(root, text) + check_stale(text)
    print(f'{target.name}: {len(lines)} lines, {failures} problem(s)')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
