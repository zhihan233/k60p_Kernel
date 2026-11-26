#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""分析设备内核验收输出（work/device-test-*）。"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST = Path(sys.argv[1]) if len(sys.argv) > 1 else sorted(ROOT.glob('work/device-test-*'))[-1]
print(f'== device test dir: {TEST}')

# lsmod 里的模块名
lsmod = TEST.joinpath('lsmod.txt').read_text(errors='replace').splitlines()
loaded = []
for line in lsmod[1:]:
    parts = line.split()
    if parts:
        loaded.append(parts[0])
loaded_set = set(loaded)
print(f'loaded modules: {len(loaded)}')

# 设备模块证据
ev = json.load(open(ROOT / 'evidence/vendor-module-versions.json'))
mods = ev['modules']
if isinstance(mods, dict):
    names = set(mods)
elif isinstance(mods, list):
    names = {m['name'] if isinstance(m, dict) else m for m in mods}
else:
    names = set()
names = {n[:-3] if n.endswith('.ko') else n for n in names}
print(f'evidence modules: {len(names)}')
print(f'evidence not loaded: {sorted(names - loaded_set)}')
print(f'loaded not in evidence: {sorted(loaded_set - names)}')

# dmesg 关键模式
dmesg = TEST.joinpath('dmesg.txt').read_text(errors='replace')
patterns = {
    'disagrees about version': r'disagrees about version',
    'CFI failure': r'CFI failure',
    'Unknown symbol': r'Unknown symbol',
    'invalid module format': r'invalid module format',
    'module verification failed': r'module verification failed',
    'no symbol version': r'no symbol version',
    'vermagic differs': r'vermagic .* differs',
    'baseband_guard': r'baseband_guard',
    'KernelSU': r'KernelSU',
    'module load failed': r'module .* failed',
}
print('\n== dmesg key patterns')
for label, pat in patterns.items():
    hits = re.findall(f'.*{pat}.*', dmesg)
    print(f'{label}: {len(hits)}')
    for h in hits[:6]:
        print('   ', h.strip()[:180])

# 关键配置
cfg_path = TEST / 'config.txt'
if cfg_path.exists():
    cfg = cfg_path.read_text(errors='replace')
    print('\n== runtime config (from /proc/config.gz)')
    keys = ['CONFIG_LTO_CLANG_THIN', 'CONFIG_LTO_CLANG_FULL', 'CONFIG_CFI_CLANG', 'CONFIG_MODVERSIONS',
            'CONFIG_BBG', 'CONFIG_KASAN_HW_TAGS', 'CONFIG_SYSVIPC', 'CONFIG_POSIX_MQUEUE',
            'CONFIG_USER_NS', 'CONFIG_IPC_NS', 'CONFIG_PID_NS', 'CONFIG_NET_NS', 'CONFIG_UTS_NS',
            'CONFIG_LRU_GEN_ENABLED', 'CONFIG_NET_SCH_FQ_CODEL', 'CONFIG_DEFAULT_FQ_CODEL',
            'CONFIG_TCP_CONG_BBR', 'CONFIG_NET_SCH_CAKE', 'CONFIG_NETFILTER_XT_MATCH_ADDRTYPE',
            'CONFIG_IP_SET', 'CONFIG_MACVLAN', 'CONFIG_DEVTMPFS', 'CONFIG_TMPFS',
            'CONFIG_IP6_NF_TARGET_MASQUERADE', 'CONFIG_TRIM_UNUSED_KSYMS', 'CONFIG_LSM=']
    for line in cfg.splitlines():
        if any(line.startswith(k) for k in keys):
            print(' ', line)
