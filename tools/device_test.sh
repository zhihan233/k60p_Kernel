#!/system/bin/sh
# SPDX-License-Identifier: MIT
# 设备内核验收脚本（root 下运行），输出到 /data/local/tmp/kern-test/
OUT=/data/local/tmp/kern-test
rm -rf "$OUT"; mkdir -p "$OUT"
exec > "$OUT/main.txt" 2>&1

echo "===== date ====="; date
echo "===== uname ====="; uname -a
echo "===== proc version ====="; cat /proc/version
echo "===== props ====="
getprop ro.build.display.id
getprop ro.product.device
getprop ro.board.platform
getprop ro.boot.verifiedbootstate
getprop ro.boot.veritymode
echo "===== root check ====="
id
cat /proc/self/attr/current 2>/dev/null
echo "===== kernelsu ====="
ls -la /data/adb/ksu 2>/dev/null | head -20
/data/adb/ksud -V 2>/dev/null || true
ls -la /data/adb/modules 2>/dev/null | head
echo "===== ksu module in lsmod ====="
lsmod | grep -i -E 'kernelsu|ksu' || echo "no kernelsu module in lsmod"
echo "===== LSM ====="
cat /sys/kernel/security/lsm
echo "===== bbg sysfs/config ====="
cat /proc/config.gz > /dev/null 2>&1 && echo "ikconfig present" || echo "ikconfig absent"
zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_BBG|CONFIG_LSM=' || true
echo "===== lsmod ====="
lsmod > "$OUT/lsmod.txt"; echo "lsmod lines: $(lsmod | wc -l)"; lsmod | head -15
echo "===== dmesg ====="
dmesg > "$OUT/dmesg.txt"; echo "dmesg bytes: $(wc -c < "$OUT/dmesg.txt")"
echo "===== vermagic of a few loaded modules ====="
for m in adsp_loader_dlkm miwill q6_dlkm; do
  f=$(find /vendor_dlkm/lib/modules /vendor/lib/modules -name "$m.ko" 2>/dev/null | head -1)
  [ -n "$f" ] && echo "$f: $(strings "$f" | grep -m1 vermagic)"
done
echo "===== module load failures ====="
dmesg | grep -i -E 'disagrees about version|CFI failure|Unknown symbol|module verification failed|invalid module format|no symbol version' | head -60 || true
echo "===== kernel config (runtime) ====="
if [ -r /proc/config.gz ]; then zcat /proc/config.gz > "$OUT/config.txt"; fi
echo "===== mm/sched ====="
cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null
cat /sys/kernel/mm/lru_gen/min_ttl_ms 2>/dev/null
cat /proc/sys/kernel/sched_util_clamp_min 2>/dev/null
echo "===== net ====="
ip -br addr
cat /proc/sys/net/ipv4/tcp_available_congestion_control
cat /proc/sys/net/ipv4/tcp_congestion_control
cat /proc/sys/net/core/default_qdisc
echo "===== battery ====="
dumpsys battery | head -25
echo "===== audio ====="
cat /proc/asound/cards
dmesg | grep -i -E 'asoc|q6|adsp|slimbus|wcd|aw88' | head -30
echo "===== camera ====="
ls -la /dev/video* 2>/dev/null | head
dmesg | grep -i -E 'cam_sync|cam_isp|csiphy|cci|camera' | head -30
echo "===== wifi ====="
dmesg | grep -i -E 'wlan0|icnss|cnss|wifi' | head -20
echo "===== cgroups/namespaces ====="
mount | grep cgroup | head
cat /proc/cgroups | head -20
cat /proc/sys/kernel/ns_last_pid 2>/dev/null
echo "===== droidspaces hints ====="
cat /proc/sys/kernel/unprivileged_userns_clone 2>/dev/null
ls /sys/fs/cgroup | head -30
echo "===== block devices ====="
ls /dev/block/mapper 2>/dev/null | head -20
echo "===== done ====="
