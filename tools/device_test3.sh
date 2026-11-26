#!/system/bin/sh
# 设备内核验收脚本 3（root）：屏幕状态 / governor / GPU / qdisc
OUT=/data/local/tmp/kern-test3
rm -rf "$OUT"; mkdir -p "$OUT"
exec > "$OUT/main3.txt" 2>&1

echo "===== wake screen ====="
dumpsys power | grep -E 'mWakefulness=|Display Power' | head -5
echo "===== before wake gov ====="
for c in 0 2 4 6 7; do echo "cpu$c gov=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor 2>/dev/null) cur=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null) max=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq 2>/dev/null) min=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_min_freq 2>/dev/null)"; done
input keyevent 224
sleep 3
echo "===== after wake ====="
dumpsys power | grep -E 'mWakefulness=' | head -3
for c in 0 2 4 6 7; do echo "cpu$c gov=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_governor 2>/dev/null) cur=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq 2>/dev/null) max=$(cat /sys/devices/system/cpu/cpu$c/cpufreq/scaling_max_freq 2>/dev/null)"; done
echo "===== gpu ====="
for f in governor cur_freq max_freq min_freq; do echo "kgsl/$f=$(cat /sys/class/kgsl/kgsl-3d0/devfreq/$f 2>/dev/null)"; done
echo "gpu_freqs=$(cat /sys/class/kgsl/kgsl-3d0/gpu_available_frequencies 2>/dev/null)"
echo "gpu_busy=$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage 2>/dev/null)"
echo "===== qdisc ====="
tc qdisc show dev wlan0 2>&1
echo "===== zram ====="
cat /sys/block/zram0/comp_algorithm 2>/dev/null
cat /sys/block/zram0/disksize 2>/dev/null
echo "===== sched/mglru ====="
cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null
cat /proc/sys/kernel/sched_util_clamp_min 2>/dev/null
cat /proc/sys/kernel/sched_util_clamp_max 2>/dev/null
echo "===== thermal zone names ====="
for z in /sys/class/thermal/thermal_zone*; do echo "$(basename $z) $(cat $z/type 2>/dev/null) $(cat $z/temp 2>/dev/null)"; done | head -20
echo "===== msm_performance / mi services ====="
ls /sys/module | grep -iE 'msm_perf|mi_|perf' | head
ps -A | grep -iE 'thermald|perfshrike|powerhint' | head
echo "===== suspend stats ====="
cat /sys/power/state 2>/dev/null
cat /sys/power/suspend_stats/success 2>/dev/null
echo "===== done3 ====="
