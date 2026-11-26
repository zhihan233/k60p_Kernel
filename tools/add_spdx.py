#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""给仓库脚本补 SPDX 许可标识（幂等）。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPDX = "SPDX-License-Identifier: GPL-2.0-only"

targets = []
targets += sorted((ROOT / 'los' / 'scripts').glob('*.sh'))
targets += sorted((ROOT / 'los' / 'scripts').glob('*.py'))
targets += sorted((ROOT / 'tools').glob('*.py'))
targets += sorted((ROOT / 'tools').glob('*.ps1'))

changed = 0
for path in targets:
    text = path.read_text(encoding='utf-8')
    if SPDX in text:
        continue
    lines = text.splitlines(keepends=True)
    insert_at = 0
    if lines and lines[0].startswith('#!'):
        insert_at = 1
    lines.insert(insert_at, f'# {SPDX}\n')
    path.write_text(''.join(lines), encoding='utf-8')
    changed += 1
    print('added SPDX:', path.relative_to(ROOT))
print(f'{changed} files updated')
