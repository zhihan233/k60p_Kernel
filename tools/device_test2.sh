#!/system/bin/sh
# SPDX-License-Identifier: MIT
# 设备内核验收脚本 2（root）：BBG 运行时、Droidspaces、网络、电源、异常检查
OUT=/data/local/tmp/kern-test2
rm -rf "$OUT"; mkdir -p "$OUT"
exec > "$OUT/main2.txt" 2>&1

echo "===== securityfs / LSM ====="
mkdir -p /sys/kernel/security 2>/dev/null
mount -t securityfs none /sys/kernel/security 2>&1
ls -la /sys/kernel/security 2>&1 | head
cat /sys/kernel/security/lsm 2>&1
echo "===== BBG dmesg ====="
dmesg | grep -i 'baseband_guard' | head -30
echo "===== Droidspaces ====="
which droidspaces 2>/dev/null
ls -la /data/adb/modules/droidspaces 2>&1 | head -20
cat /data/adb/modules/droidspaces/module.prop 2>/dev/null
droidspaces --version 2>&1 | head -3
droidspaces --help 2>&1 | head -15
ps -A | grep -i droid | head
ls -la /sys/fs/cgroup/droidspaces 2>&1 | head
echo "===== power supply ====="
for f in status current_now voltage_now temperature capacity charge_counter input_current_limit constant_charge_current; do
  v=$(cat /sys/class/power_supply/battery/$f 2>/dev/null); echo "battery/$f=$v"
done
ls /sys/class/power_supply/
echo "===== network ====="
ip route | head -10
ping -c 3 -W 2 223.5.5.5 2>&1 | tail -3
ping -c 3 -W 2 www.baidu.com 2>&1 | tail -3
echo "===== kernel anomalies ====="
echo "avc_denied_count: $(dmesg | grep -c 'avc: denied')"
dmesg | grep -iE 'Unable to handle kernel|kernel BUG|WARNING:|Oops|panic|Call trace' | head -15
dmesg | grep -iE 'disagrees about version|CFI failure|Unknown symbol|invalid module format' | head -10
echo "===== cpu/governor ====="
for c in 0 4 7; do echo "cpu$c: $(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor 2>/dev/null) cur=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null) max=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq 2>/dev/null)"; done
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null
echo "===== thermal ====="
ls /sys/class/thermal/ | head -8
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null
echo "===== audio/camera service ====="
ps -A | grep -E 'cameraserver|audioserver|audiohalservice|cameraservice' | head
getprop | grep -E 'init.svc.(cameraserver|audioserver|vendor.audio)' | head
echo "===== zram/swap ====="
cat /proc/swaps
echo "===== modules count ====="
echo "lsmod lines: $(lsmod | wc -l)"
echo "===== done2 ====="
