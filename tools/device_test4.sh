#!/system/bin/sh
# SPDX-License-Identifier: MIT
# 设备内核验收脚本 4（root）：Droidspaces 实际运行 / 蓝牙 / 显示 / 命名空间
OUT=/data/local/tmp/kern-test4
rm -rf "$OUT"; mkdir -p "$OUT"
exec > "$OUT/main4.txt" 2>&1

echo "===== droidspaces daemon ====="
ps -A | grep -i droidspaces
pid=$(ps -A | grep -i droidspaces | grep -v grep | head -1 | awk '{print $2}')
echo "pid=$pid"
[ -n "$pid" ] && { tr '\0' ' ' < /proc/$pid/cmdline; echo; }
echo "===== find droidspaces binaries ====="
find /data/adb /data/app /system/bin /system/xbin /vendor/bin /debug_ramdisk -maxdepth 6 -name 'droidspaces*' 2>/dev/null | head -20
echo "===== droidspaces dirs ====="
ls -la /data/adb/droidspaces 2>&1 | head -15
ls -la /data/adb/modules/droidspaces/ 2>&1 | head -20
echo "===== cgroup delegation ====="
cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null
cat /sys/fs/cgroup/droidspaces/cgroup.controllers 2>/dev/null
ls /sys/fs/cgroup/droidspaces 2>/dev/null | head
echo "===== namespaces ====="
ls -l /proc/1/ns
unshare -Ur true 2>&1; echo "unshare -Ur rc=$?"
unshare -Urmpf true 2>&1; echo "unshare -Urmpf rc=$?"
echo "===== bluetooth ====="
dmesg | grep -iE 'bluetooth|hci|btusb' | head -8
ps -A | grep -i bluetooth | head -3
getprop | grep -iE 'init.svc.*bluetooth|bluetooth.*enable' | head -5
echo "===== display ====="
cat /sys/class/backlight/*/brightness 2>/dev/null
dumpsys display 2>/dev/null | grep -E 'mScreenState|DisplayDeviceInfo' | head -3
echo "===== touch/input ====="
getevent -p 2>/dev/null | head -3 || true
ls /dev/input/ | head
echo "===== tsens/thermal trip ====="
dmesg | grep -iE 'tsens|thermal.*trip|qmi.*thermal' | head -5
echo "===== done4 ====="
