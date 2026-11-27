#!/system/bin/sh
# SPDX-License-Identifier: MIT
# 设备内核验收脚本 6：BBG 白名单分区放行 + 蜂窝/异常统计
OUT=/data/local/tmp/kern-test6
rm -rf "$OUT"; mkdir -p "$OUT"
exec > "$OUT/main6.txt" 2>&1

echo "===== BBG allowlist test on boot_a ====="
DEV=$(readlink -f /dev/block/by-name/boot_a 2>/dev/null)
ORIG=$(stat -c '%a' "$DEV" 2>/dev/null)
echo "dev=$DEV orig_mode=$ORIG"
chmod 640 "$DEV"; echo "chmod 640 boot_a rc=$?"
NOW=$(stat -c '%a' "$DEV" 2>/dev/null); echo "mode now=$NOW"
chmod "$ORIG" "$DEV" 2>/dev/null; echo "restore rc=$? mode=$(stat -c '%a' "$DEV" 2>/dev/null)"
echo "===== protected modem_a test ====="
DEV2=$(readlink -f /dev/block/by-name/modem_a 2>/dev/null)
echo "dev=$DEV2"
chmod 640 "$DEV2"; echo "chmod modem_a rc=$?"
echo "===== cellular ====="
getprop gsm.sim.state
getprop gsm.network.type
getprop gsm.operator.alpha
dumpsys telephony.registry 2>/dev/null | grep -E 'mServiceState=|mDataConnectionState=|mSignalStrength=' | head -6
echo "===== wifi info ====="
dumpsys wifi 2>/dev/null | grep -E 'mWifiInfo|Wi-Fi is' | head -3
echo "===== kernel anomaly counts ====="
for p in 'WARNING:' 'BUG:' 'Oops' 'Unable to handle kernel' 'Call trace' 'kernel panic' 'disagrees about version' 'CFI failure' 'Unknown symbol'; do
  echo "$p => $(dmesg | grep -c "$p")"
done
cat /proc/sys/kernel/tainted
cat /proc/modules | wc -l
echo "===== dmesg tail ====="
dmesg | tail -10
echo "===== done6 ====="
