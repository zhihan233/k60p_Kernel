#!/system/bin/sh
# SPDX-License-Identifier: MIT
# BBG 防格机功能验证（root）：受保护分区 setattr 应被拒绝；boot 属白名单应允许（测试后恢复）
OUT=/data/local/tmp/kern-test5
rm -rf "$OUT"; mkdir -p "$OUT"
exec > "$OUT/main5.txt" 2>&1

echo "===== partitions ====="
ls -l /dev/block/by-name/ 2>/dev/null | head -40
echo "===== original modes ====="
for p in modem persist boot; do
  n=/dev/block/by-name/$p
  if [ -e "$n" ]; then
    r=$(readlink -f "$n")
    echo "$p -> $r mode=$(stat -c '%a' "$r" 2>/dev/null) owner=$(stat -c '%U:%G' "$r" 2>/dev/null)"
  else
    echo "$p -> MISSING"
  fi
done
echo "===== dmesg marker before ====="
dmesg | wc -l
echo "===== test 1: chmod on protected 'modem' (expect EPERM from BBG) ====="
DEV=$(readlink -f /dev/block/by-name/modem 2>/dev/null)
echo "dev=$DEV"
chmod 600 "$DEV"; echo "chmod modem rc=$?"
stat -c 'modem mode now=%a' "$DEV" 2>/dev/null
echo "===== test 2: chmod on protected 'persist' (expect EPERM from BBG) ====="
DEV2=$(readlink -f /dev/block/by-name/persist 2>/dev/null)
echo "dev=$DEV2"
chmod 600 "$DEV2"; echo "chmod persist rc=$?"
echo "===== test 3: chmod on allowlisted 'boot' (expect success) ====="
DEV3=$(readlink -f /dev/block/by-name/boot 2>/dev/null)
ORIG=$(stat -c '%a' "$DEV3" 2>/dev/null)
echo "dev=$DEV3 orig_mode=$ORIG"
chmod 600 "$DEV3"; echo "chmod boot rc=$?"
stat -c 'boot mode now=%a' "$DEV3" 2>/dev/null
chmod "$ORIG" "$DEV3" 2>/dev/null; echo "restore rc=$? mode=$(stat -c '%a' "$DEV3" 2>/dev/null)"
echo "===== dmesg BBG deny lines ====="
dmesg | grep -i 'baseband_guard' | tail -15
echo "===== selinux context of test shell ====="
cat /proc/self/attr/current 2>/dev/null
echo "===== done5 ====="
